import Combine
import CryptoKit
import Foundation
import Network
import OSLog

/// Serves protocol v1 to the paired phone over two paths at once: TCP
/// advertised on the LAN via Bonjour, and the punched UDP path that works
/// from anywhere (GoKit/Transport/Punch.swift). The phone prefers whichever
/// answers, and everything above the transport is identical either way.
/// Structure lifted from Tomte's AgentServer; what each request *does* is
/// opencodego's own, routed through OpenCodeAdapter.
///
/// Every connection must complete the Wire handshake: a challenge answered
/// with an HMAC keyed by the pairing-derived channel key, after which all
/// traffic is sealed. An unpaired Mac refuses everything — neither being on
/// the same Wi-Fi nor knowing the address is an identity.
@MainActor
final class GoServer: ObservableObject {
    private let logger = Logger(subsystem: "com.timwilliams.opencodego", category: "server")
    private var listener: NWListener?
    private let punch = PunchListener()
    private var pairingObserver: NSObjectProtocol?
    /// Where the running OpenCode instance is, or nil while it's down —
    /// requests during a restart get an honest transient failure.
    private let adapter: () -> OpenCodeAdapter?

    init(adapter: @escaping () -> OpenCodeAdapter?) {
        self.adapter = adapter
    }

    /// The user's kill switch: while paused, the Mac neither advertises nor
    /// listens on either path — remotely, the companion doesn't exist.
    @Published private(set) var paused = false

    func setPaused(_ value: Bool) {
        guard value != paused else { return }
        paused = value
        if value {
            listener?.cancel()
            listener = nil
            punch.stop()
            logger.notice("remote access paused")
        } else {
            start()
        }
    }

    func start() {
        guard !paused else { return }
        punch.onStream = { [weak self] stream in
            guard let self else { return }
            Connection(stream, adapter: adapter, logger: logger).start()
        }
        // The punched path needs a pairing to derive its keys from, and
        // PunchListener.start() bails quietly without one — so re-kick it
        // whenever pairing changes, not just at launch. (Tomte re-triggered
        // this from its Devices pane; a menu bar app has no such moment.)
        punch.start()
        if pairingObserver == nil {
            pairingObserver = NotificationCenter.default.addObserver(
                forName: PairingStore.changed, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.paused else { return }
                    self.punch.start()
                }
            }
        }
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let listener = try NWListener(
                using: params,
                on: NWEndpoint.Port(rawValue: Wire.port)!
            )
            listener.service = NWListener.Service(type: Wire.bonjourType)
            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                Task { @MainActor in
                    Connection(
                        TCPTransport(conn), adapter: self.adapter, logger: self.logger
                    ).start()
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case let .failed(error) = state {
                    self?.logger.error("listener failed: \(error.localizedDescription)")
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            logger.notice("serving on \(Wire.port), advertising \(Wire.bonjourType)")
        } catch {
            logger.error("listener setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// One accepted connection, over either transport: challenge → auth → sealed
/// request/response, then it closes. Self-retaining until the transport dies.
@MainActor
private final class Connection {
    private let transport: WireTransport
    private let adapter: () -> OpenCodeAdapter?
    private let logger: Logger
    private var framer = LineFramer()
    private let serverNonce = Wire.Security.nonce()
    private var channel: Wire.SecureChannel?
    private var retainCycle: Connection?
    private var announced = false
    private var peerCompresses = false

    init(
        _ transport: WireTransport,
        adapter: @escaping () -> OpenCodeAdapter?,
        logger: Logger
    ) {
        self.transport = transport
        self.adapter = adapter
        self.logger = logger
    }

    func start() {
        retainCycle = self
        transport.onBytes = { [weak self] data in
            guard let self else { return }
            for frame in framer.push(data) { handle(frame) }
        }
        transport.onClosed = { [weak self] _ in
            guard let self else { return }
            if announced {
                announced = false
                PhoneLinkMonitor.shared.noteDisconnected()
            }
            retainCycle = nil
        }
        transport.start()
        var challenge = Wire.Event(kind: "challenge")
        challenge.text = serverNonce
        writePlain(challenge)
    }

    private func handle(_ frame: Data) {
        guard let channel else {
            authenticate(frame)
            return
        }
        guard let opened = channel.open(frame),
              let plaintext = Wire.Squeeze.unpack(opened),
              let request = try? JSONDecoder().decode(Wire.Request.self, from: plaintext)
        else {
            logger.error("dropping connection: undecryptable or malformed frame")
            transport.close()
            return
        }
        serve(request)
    }

    // MARK: - Handshake

    private func authenticate(_ frame: Data) {
        guard let auth = try? JSONDecoder().decode(Wire.Auth.self, from: frame),
              auth.kind == "auth"
        else {
            refuse("Expected authentication.")
            return
        }
        guard PairingStore.load() != nil, let channelKey = try? PairingStore.channelKey() else {
            refuse("This Mac isn't paired with an iPhone yet. Open Devices in the Mac menu bar app to pair.")
            return
        }
        guard Wire.Security.verify(
            tag: auth.tag, channelKey: channelKey,
            serverNonce: serverNonce, clientNonce: auth.nonce, name: auth.name
        ) else {
            logger.error("auth failed for '\(auth.name, privacy: .public)'")
            refuse("This device isn't paired with this Mac.")
            return
        }
        let sessionKey = Wire.Security.sessionKey(
            channelKey: channelKey, serverNonce: serverNonce, clientNonce: auth.nonce
        )
        channel = Wire.SecureChannel(key: sessionKey)
        peerCompresses = auth.compress == true
        announced = true
        PhoneLinkMonitor.shared.noteAuthenticated(name: auth.name)
        logger.notice("authenticated '\(auth.name, privacy: .public)'")
        Task { @MainActor in
            var ready = Wire.Event(kind: "ready")
            ready.compress = true
            ready.capabilities = try? await self.adapter()?.capabilities()
            self.write(ready)
        }
    }

    private func refuse(_ message: String) {
        var e = Wire.Event(kind: "failed")
        e.text = message
        writePlain(e)
        writePlain(Wire.Event(kind: "done"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [transport] in transport.close() }
    }

    // MARK: - Requests

    private func serve(_ request: Wire.Request) {
        guard let adapter = adapter() else {
            var e = Wire.Event(kind: "failed")
            e.text = "OpenCode is starting on your Mac — try again in a moment."
            e.transient = true
            write(e)
            write(Wire.Event(kind: "done"))
            return
        }
        switch request.kind {
        case "status":
            answer { var e = Wire.Event(kind: "status")
                     e.capabilities = try await adapter.capabilities()
                     return [e] }
        case "projects":
            answer { var e = Wire.Event(kind: "projects")
                     e.projects = try await adapter.projects()
                     return [e] }
        case "sessions":
            answer { var e = Wire.Event(kind: "sessions")
                     e.sessions = try await adapter.sessions()
                     return [e] }
        case "prompt":
            servePrompt(request, adapter: adapter)
        case "resume":
            serveResume(request)
        case "permission":
            servePermissionReply(request, adapter: adapter)
        case "pending":
            answer {
                guard let directory = request.project else { return [] }
                var e = Wire.Event(kind: "pending")
                e.permissions = try await adapter.pendingPermissions(directory: directory)
                return [e]
            }
        case "abort":
            answer {
                guard let session = request.session, let directory = request.project else { return [] }
                try await adapter.abort(sessionID: session, directory: directory)
                return []
            }
        case "transcript":
            answer {
                guard let session = request.session, let directory = request.project else { return [] }
                var events: [Wire.Event] = []
                for part in try await adapter.transcript(sessionID: session, directory: directory) {
                    var e = Wire.Event(kind: "part")
                    e.part = part
                    e.session = session
                    events.append(e)
                }
                var diff = Wire.Event(kind: "diff")
                diff.diffs = try await adapter.turnDiffs(sessionID: session, directory: directory)
                diff.session = session
                events.append(diff)
                return events
            }
        default:
            var e = Wire.Event(kind: "failed")
            e.text = "Unknown request."
            write(e)
            write(Wire.Event(kind: "done"))
        }
    }

    /// The one-shot request shape: compute events, send them, close with
    /// `done`; any error becomes a `failed` the phone can show.
    private func answer(_ work: @escaping () async throws -> [Wire.Event]) {
        Task { @MainActor in
            do {
                for event in try await work() { self.write(event) }
            } catch {
                var e = Wire.Event(kind: "failed")
                e.text = error.localizedDescription
                self.write(e)
            }
            self.write(Wire.Event(kind: "done"))
        }
    }

    /// Hands the turn to `LiveTurns` and then does nothing but relay. The
    /// turn deliberately doesn't belong to this connection: the phone's
    /// socket dies every time iOS suspends the app, and an answer owned by
    /// the socket dies with it.
    private func servePrompt(_ request: Wire.Request, adapter: OpenCodeAdapter) {
        let id = request.turn ?? UUID().uuidString
        LiveTurns.shared.start(id, directory: request.project, sink: self) { emit in
            await TurnRunner.run(request, adapter: adapter, emit: emit)
        }
    }

    /// A phone reconnecting to an answer it lost the socket to.
    private func serveResume(_ request: Wire.Request) {
        guard let id = request.turn else {
            write(Wire.Event(kind: "unknown"))
            return
        }
        guard LiveTurns.shared.resume(id, from: request.from ?? 0, sink: self) else {
            // Not a failure: the question never got here, or its answer aged
            // out. The phone should ask again rather than show an error.
            logger.notice("resume: no such turn")
            write(Wire.Event(kind: "unknown"))
            return
        }
        logger.notice("resumed turn from event \(request.from ?? 0)")
    }

    private func servePermissionReply(_ request: Wire.Request, adapter: OpenCodeAdapter) {
        answer {
            guard let id = request.permissionID, let directory = request.project,
                  let reply = request.reply
            else { return [] }
            try await adapter.replyPermission(id: id, directory: directory, reply: reply)
            return []
        }
    }

    // MARK: - Writes

    /// Pre-handshake only: the challenge and refusals.
    private func writePlain(_ event: Wire.Event) {
        guard let data = Wire.encode(event) else { return }
        transport.send(data)
    }

    private func write(_ event: Wire.Event) {
        guard let channel,
              let plain = try? JSONEncoder().encode(event)
        else { return }
        let body = peerCompresses ? Wire.Squeeze.pack(plain) : plain
        guard let sealed = channel.seal(body) else { return }
        transport.send(sealed)
    }
}

extension Connection: TurnSink {
    func deliver(_ event: Wire.Event) { write(event) }
}

/// Runs one prompt turn against OpenCode: ensure a session, subscribe to its
/// event stream, fire the prompt, and translate what happens into protocol
/// v1 events until the session goes idle.
enum TurnRunner {
    @MainActor
    static func run(
        _ request: Wire.Request, adapter: OpenCodeAdapter,
        emit: @escaping (Wire.Event) -> Void
    ) async {
        func fail(_ message: String) {
            var e = Wire.Event(kind: "failed")
            e.text = message
            emit(e)
            emit(Wire.Event(kind: "done"))
        }
        guard let directory = request.project, let text = request.text else {
            fail("The prompt was missing its project or text.")
            return
        }
        do {
            let sessionID: String
            if let existing = request.session {
                sessionID = existing
            } else {
                sessionID = try await adapter.createSession(directory: directory)
            }
            // Tell the phone which session this turn landed in before
            // anything streams — it's what makes "continue this thread
            // later" possible.
            var opened = Wire.Event(kind: "status")
            opened.session = sessionID
            emit(opened)

            var providerID = request.providerID
            var modelID = request.modelID
            if providerID == nil || modelID == nil {
                guard let fallback = try await adapter.defaultModel() else {
                    fail("No model is configured in OpenCode on your Mac.")
                    return
                }
                providerID = providerID ?? fallback.providerID
                modelID = modelID ?? fallback.modelID
            }

            // Subscribe before prompting so nothing falls between.
            let events = adapter.events(directory: directory)
            try await adapter.promptAsync(
                sessionID: sessionID, directory: directory, text: text,
                providerID: providerID!, modelID: modelID!
            )

            for try await event in events {
                let type = event["type"] as? String ?? ""
                let properties = event["properties"] as? [String: Any] ?? [:]
                switch type {
                case "message.part.updated":
                    guard let part = properties["part"] as? [String: Any],
                          part["sessionID"] as? String == sessionID,
                          let mapped = OpenCodeAdapter.turnPart(from: part, role: "assistant")
                    else { continue }
                    var e = Wire.Event(kind: "part")
                    e.part = mapped
                    e.session = sessionID
                    emit(e)
                // 1.18 asks with `permission.asked`; 1.16-era servers said
                // `permission.updated`. Same skew note as the adapter.
                case "permission.asked", "permission.updated":
                    guard let mapped = OpenCodeAdapter.permission(from: properties),
                          mapped.sessionID == nil || mapped.sessionID == sessionID
                    else { continue }
                    var e = Wire.Event(kind: "permission")
                    e.permission = mapped
                    e.session = sessionID
                    emit(e)
                case "session.error":
                    guard properties["sessionID"] as? String == sessionID else { continue }
                    fail("The agent hit an error on your Mac.")
                    return
                case "session.idle":
                    guard properties["sessionID"] as? String == sessionID else { continue }
                    var diff = Wire.Event(kind: "diff")
                    diff.diffs = (try? await adapter.turnDiffs(
                        sessionID: sessionID, directory: directory
                    )) ?? []
                    diff.session = sessionID
                    emit(diff)
                    emit(Wire.Event(kind: "idle"))
                    emit(Wire.Event(kind: "done"))
                    return
                default:
                    continue
                }
            }
            // The SSE stream ended without an idle — OpenCode went away.
            fail("Lost OpenCode's event stream on your Mac.")
        } catch {
            fail(error.localizedDescription)
        }
    }
}
