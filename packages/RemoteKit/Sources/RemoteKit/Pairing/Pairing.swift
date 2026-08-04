import CloudKit
import CryptoKit
import Foundation
import OSLog
import Security
#if os(iOS)
import UIKit
#endif

/// Device pairing, ported from the validated Phase-0 spike (pairing-spike/).
///
/// Scope in the app: pairing establishes *identity* — each device keeps a
/// Curve25519 private key in its local keychain, exchanges public halves
/// through the shared-Apple-ID CloudKit private database, and the user
/// confirms a 6-digit code shown on both screens. The derived shared secret
/// then authenticates and encrypts the LAN channel (see Wire).
///
/// The same rendezvous record then carries the devices' address candidates,
/// so the cross-network transport (see Punch) has somewhere to meet without
/// a server of ours in the middle. Pairing itself needs none of that —
/// CloudKit is the rendezvous for both.
public enum Pairing {
    public static let cloudContainerID = "iCloud.com.timwilliams.opencodego"
    static let keychainService = "com.timwilliams.opencodego"
}

// MARK: - Roles and records

public enum DeviceRole: String, Codable, Sendable {
    case mac
    case phone

    /// One Mac and one phone per Apple ID for now, so record names are
    /// fixed and fetched by ID — no queries, no queryable-index setup.
    var recordName: String { "peer-\(rawValue)" }
    public var peer: DeviceRole { self == .mac ? .phone : .mac }

    /// The role this build plays.
    public static var current: DeviceRole {
        #if os(macOS)
        .mac
        #else
        .phone
        #endif
    }
}

/// What this device calls itself on the other one's screen.
public enum DeviceIdentity {
    public static var name: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }
}

struct PeerRecord {
    var deviceName: String
    var role: DeviceRole
    var pubKeyAgreement: Data
    var pubKeySigning: Data
    var heartbeatAt: Date
    var approvedAt: Date?
    /// "ip:port" candidates this device can currently be reached at — its
    /// LAN addresses plus the reflexive one STUN reported. Empty until the
    /// device has published any.
    var endpoints: [String] = []
    /// Set by the phone when it starts dialling, so the Mac knows to punch
    /// back now rather than at its next lazy poll.
    var connectRequestedAt: Date?
}

public enum PairingError: Error, LocalizedError {
    case keychain(OSStatus)
    case notPaired
    case network(String)

    public var errorDescription: String? {
        switch self {
        case let .keychain(s): return "keychain error \(s)"
        case .notPaired: return "No paired device."
        case let .network(m): return m
        }
    }
}

// MARK: - Key material

/// Device-local key material. Private keys are generic-password keychain
/// items, non-synchronizable — only public halves ever reach CloudKit.
enum PairingKeyStore {
    static func agreementKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let data = try read(tag: "pairing.agreement") {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try write(tag: "pairing.agreement", data: key.rawRepresentation)
        return key
    }

    static func signingKey() throws -> Curve25519.Signing.PrivateKey {
        if let data = try read(tag: "pairing.signing") {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.Signing.PrivateKey()
        try write(tag: "pairing.signing", data: key.rawRepresentation)
        return key
    }

    private static func query(tag: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Pairing.keychainService,
            kSecAttrAccount as String: tag,
        ]
    }

    private static func read(tag: String) throws -> Data? {
        var q = query(tag: tag)
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        // -25293: the item exists but this binary may not read it. On macOS
        // that means the keychain ACL was written by a differently-signed
        // build of this app — a re-sign, a move, an unsigned local build.
        //
        // An unreadable private key is a dead pairing by definition: the
        // channel key can't be derived, so nothing can authenticate with it
        // ever again. Holding onto it would leave the user stuck at an
        // error with no way forward, including through the re-pair that
        // would otherwise fix everything. So drop it and mint a fresh one;
        // the peer's records are rewritten by the next pairing anyway.
        if status == errSecAuthFailed || status == errSecInteractionNotAllowed {
            SecItemDelete(query(tag: tag) as CFDictionary)
            return nil
        }
        guard status == errSecSuccess else { throw PairingError.keychain(status) }
        return out as? Data
    }

    private static func write(tag: String, data: Data) throws {
        var q = query(tag: tag)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        var status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // A leftover we just failed to read, or a partial write. The
            // add is the authority here, so replace rather than keep.
            SecItemDelete(query(tag: tag) as CFDictionary)
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw PairingError.keychain(status)
        }
    }

    /// Forget this device's key material entirely, so the next pairing
    /// starts from new keys. Used by unpair — a re-pair that reuses a key
    /// the peer has already rejected is not a fresh start.
    static func reset() {
        for tag in ["pairing.agreement", "pairing.signing"] {
            SecItemDelete(query(tag: tag) as CFDictionary)
        }
    }
}

// MARK: - Session crypto

/// X25519 → HKDF channel key, plus the 6-digit short-auth string both
/// screens display during pairing.
public struct PairingCrypto {
    public let channelKey: SymmetricKey
    public let sas: String

    init(myKey: Curve25519.KeyAgreement.PrivateKey, peerPub: Data) throws {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPub)
        let secret = try myKey.sharedSecretFromKeyAgreement(with: peer)
        channelKey = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("opencodego-v1".utf8),
            sharedInfo: Data("channel".utf8),
            outputByteCount: 32
        )
        sas = Self.shortAuthString(myKey.publicKey.rawRepresentation, peerPub)
    }

    /// Order-independent 6-digit code over both public keys. Matching
    /// numbers on both screens rules out a rendezvous-level MITM.
    static func shortAuthString(_ a: Data, _ b: Data) -> String {
        let sorted = [a, b].sorted { $0.lexicographicallyPrecedes($1) }
        let digest = SHA256.hash(data: sorted[0] + sorted[1])
        let n = digest.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        return String(format: "%06d", n % 1_000_000)
    }
}

// MARK: - Persisted pairing state

/// The one fact pairing produces: who my peer is. The peer's public key is
/// public data, so UserDefaults is fine; the channel key is re-derived from
/// the keychain private key on demand rather than stored.
public struct PairedDevice: Codable, Equatable {
    public var name: String
    public var role: DeviceRole
    public var pubKeyAgreement: Data
    public var pairedAt: Date
}

public enum PairingStore {
    private static let key = "opencodego.pairedDevice"
    private static let everKey = "opencodego.hasEverPaired"
    public static let changed = Notification.Name("PairingStore.changed")

    /// Whether this device has *ever* completed a pairing, which is not the
    /// same question as whether it is paired now and deliberately survives
    /// `clear()`.
    ///
    /// It exists to decide who needs selling to. Someone who has never paired
    /// may not know the Mac app exists, and the phone's connect screen is the
    /// only place that can tell them. Someone who has paired before knows
    /// exactly what they are missing and is looking at that screen because
    /// something is broken or they unpaired on purpose — pitching the product
    /// to them is noise sitting between them and the fix.
    public static var hasEverPaired: Bool {
        UserDefaults.standard.bool(forKey: everKey)
    }

    public static func load() -> PairedDevice? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PairedDevice.self, from: data)
    }

    public static func save(_ device: PairedDevice) {
        if let data = try? JSONEncoder().encode(device) {
            UserDefaults.standard.set(data, forKey: key)
        }
        UserDefaults.standard.set(true, forKey: everKey)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// The symmetric key shared with the paired device, derived fresh from
    /// the local private key and the stored peer public key.
    public static func channelKey() throws -> SymmetricKey {
        guard let peer = load() else { throw PairingError.notPaired }
        let mine = try PairingKeyStore.agreementKey()
        return try PairingCrypto(myKey: mine, peerPub: peer.pubKeyAgreement).channelKey
    }
}

// MARK: - CloudKit rendezvous

/// Thin CloudKit private-database client for the rendezvous records.
final class PairingCloud: Sendable {
    private let db = CKContainer(identifier: Pairing.cloudContainerID).privateCloudDatabase

    func accountStatus() async throws -> CKAccountStatus {
        try await CKContainer(identifier: Pairing.cloudContainerID).accountStatus()
    }

    /// Which parts of our record a write is responsible for.
    ///
    /// Two independent things now write this record: the pairing screen and
    /// the transport's candidate publisher. They run at the same time on a
    /// phone that is pairing, and a blanket write from either would erase the
    /// other's fields — an approval lost this way stalls pairing forever, and
    /// erased candidates make the Mac punch at nothing. So every write names
    /// what it owns, and leaves the rest of the record alone.
    struct Fields: OptionSet {
        let rawValue: Int
        /// Name and public keys. Always written: whichever writer creates the
        /// record first must leave something the peer can identify.
        static let identity = Fields(rawValue: 1 << 0)
        static let approval = Fields(rawValue: 1 << 1)
        static let endpoints = Fields(rawValue: 1 << 2)
        static let connectRequest = Fields(rawValue: 1 << 3)
    }

    /// Upsert our own DevicePeer record (fetch-modify-save; retries once on
    /// a lost conflict since we are the only writer of our own record).
    func upsertSelf(_ me: PeerRecord, fields: Fields) async throws {
        let id = CKRecord.ID(recordName: me.role.recordName)
        let record: CKRecord
        if let existing = try? await db.record(for: id) {
            record = existing
        } else {
            record = CKRecord(recordType: "DevicePeer", recordID: id)
        }
        apply(me, fields: fields, to: record)
        do {
            _ = try await db.save(record)
        } catch let e as CKError where e.code == .serverRecordChanged {
            if let server = e.serverRecord {
                apply(me, fields: fields, to: server)
                _ = try await db.save(server)
            }
        }
    }

    private func apply(_ me: PeerRecord, fields: Fields, to record: CKRecord) {
        record["deviceName"] = me.deviceName
        record["role"] = me.role.rawValue
        record["pubKeyAgreement"] = me.pubKeyAgreement
        record["pubKeySigning"] = me.pubKeySigning
        record["heartbeatAt"] = me.heartbeatAt
        if fields.contains(.approval) { record["approvedAt"] = me.approvedAt }
        if fields.contains(.endpoints) { record["endpoints"] = me.endpoints }
        if fields.contains(.connectRequest) {
            record["connectRequestedAt"] = me.connectRequestedAt
        }
    }

    /// Fetch the counterpart's record, nil until it exists.
    func fetchPeer(of role: DeviceRole) async throws -> PeerRecord? {
        let id = CKRecord.ID(recordName: role.peer.recordName)
        do {
            let r = try await db.record(for: id)
            guard
                let name = r["deviceName"] as? String,
                let roleRaw = r["role"] as? String,
                let role = DeviceRole(rawValue: roleRaw),
                let agree = r["pubKeyAgreement"] as? Data,
                let sign = r["pubKeySigning"] as? Data,
                let beat = r["heartbeatAt"] as? Date
            else { return nil }
            return PeerRecord(
                deviceName: name,
                role: role,
                pubKeyAgreement: agree,
                pubKeySigning: sign,
                heartbeatAt: beat,
                approvedAt: r["approvedAt"] as? Date,
                endpoints: r["endpoints"] as? [String] ?? [],
                connectRequestedAt: r["connectRequestedAt"] as? Date
            )
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        }
    }

    /// Remove both records so a future pairing starts clean.
    func reset() async {
        for role in [DeviceRole.mac, .phone] {
            _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: role.recordName))
        }
    }
}

// MARK: - Session state machine

/// Runs one pairing attempt while its screen is visible: publish own record,
/// poll for the peer, show the SAS, and — once both sides have approved —
/// persist the peer and stop. Both apps drive the same machine.
@MainActor
public final class PairingSession: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case initializing
        /// iCloud unavailable; message explains what to do.
        case noICloud(String)
        case waitingForPeer
        case peerFound(name: String, sas: String)
        case waitingForPeerApproval(name: String, sas: String)
        case paired(name: String)
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle

    private let role = DeviceRole.current
    private let cloud = PairingCloud()
    private var agreementKey: Curve25519.KeyAgreement.PrivateKey?
    private var crypto: PairingCrypto?
    private var peer: PeerRecord?
    private var approvedLocally = false
    private var loop: Task<Void, Never>?
    private static let logger = Logger(
        subsystem: "com.timwilliams.opencodego", category: "pairing"
    )

    public init() {}

    public var deviceName: String { DeviceIdentity.name }

    public func start() {
        guard loop == nil else { return }
        approvedLocally = false
        crypto = nil
        peer = nil
        phase = .initializing
        loop = Task { await run() }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        if case .paired = phase {} else { phase = .idle }
    }

    public func approve() {
        approvedLocally = true
        if case let .peerFound(name, sas) = phase {
            phase = .waitingForPeerApproval(name: name, sas: sas)
        }
        Task { try? await publishSelf() }
    }

    /// Forget the paired device and wipe the rendezvous records so both
    /// sides can start over.
    public func unpair() {
        PairingStore.clear()
        // Key material goes too. Leaving it behind is what turns "unpair
        // and try again" into a re-pair that still can't read its own key.
        PairingKeyStore.reset()
        stop()
        Task { await cloud.reset() }
    }

    private func run() async {
        do {
            let status = try await cloud.accountStatus()
            guard status == .available else {
                phase = .noICloud(
                    "Sign into iCloud on this device — pairing uses your iCloud account to find your other device, and only ever shares public keys."
                )
                return
            }
            agreementKey = try PairingKeyStore.agreementKey()
            try await publishSelf()
            phase = .waitingForPeer
            Self.logger.notice("published \(self.role.rawValue, privacy: .public) record; waiting for \(self.role.peer.rawValue, privacy: .public)")

            while !Task.isCancelled {
                try await tick()
                if case .paired = phase { return }
                try await Task.sleep(for: .seconds(3))
            }
        } catch is CancellationError {
            // stopped by the screen going away — not a failure
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func tick() async throws {
        guard let agreementKey else { return }
        guard let found = try await cloud.fetchPeer(of: role) else {
            try await publishSelf()
            return
        }
        // A record with a stale heartbeat is a leftover, not a live pairing
        // attempt — pairing requires both apps open, so demand freshness
        // before showing a name or honoring an approval.
        let fresh = Date().timeIntervalSince(found.heartbeatAt) < 120
        if peer?.pubKeyAgreement != found.pubKeyAgreement {
            crypto = try PairingCrypto(myKey: agreementKey, peerPub: found.pubKeyAgreement)
            Self.logger.notice("peer '\(found.deviceName, privacy: .public)' found (heartbeat \(fresh ? "fresh" : "stale", privacy: .public))")
        }
        peer = found
        guard let crypto, fresh else {
            try await publishSelf()
            return
        }

        switch phase {
        case .waitingForPeer:
            phase = .peerFound(name: found.deviceName, sas: crypto.sas)
        case .peerFound, .waitingForPeerApproval:
            if approvedLocally, found.approvedAt != nil {
                complete(with: found)
                return
            }
        default:
            break
        }
        try await publishSelf()
    }

    private func complete(with found: PeerRecord) {
        PairingStore.save(PairedDevice(
            name: found.deviceName,
            role: found.role,
            pubKeyAgreement: found.pubKeyAgreement,
            pairedAt: Date()
        ))
        phase = .paired(name: found.deviceName)
        Self.logger.notice("paired with '\(found.deviceName, privacy: .public)'")
        loop?.cancel()
        loop = nil
    }

    private func publishSelf() async throws {
        guard let agreementKey else { return }
        try await cloud.upsertSelf(PeerRecord(
            deviceName: deviceName,
            role: role,
            pubKeyAgreement: agreementKey.publicKey.rawRepresentation,
            pubKeySigning: (try PairingKeyStore.signingKey()).publicKey.rawRepresentation,
            heartbeatAt: Date(),
            approvedAt: approvedLocally ? Date() : nil
        ), fields: [.identity, .approval])
    }
}
