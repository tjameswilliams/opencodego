import RemoteKit
import CryptoKit
import Foundation
import Network
import UIKit

/// One request to the paired Mac: find a path → Wire handshake → sealed
/// request → stream of sealed events. The phone's single implementation of
/// "talk to my Mac", ported from Tomte with the attachment shaping removed
/// (protocol v1 carries no payloads that need it yet).
///
/// Two paths, tried in that order:
///
/// 1. **Bonjour + TCP**, when the Mac is on the same network.
/// 2. **The punched UDP path** (RemoteKit/Transport/Punch.swift), which works
///    from anywhere. The devices meet through the address candidates they
///    publish to the user's own CloudKit record; no server of ours.
///
/// The handshake and everything above it are identical on both, so the rest
/// of this file doesn't know or care which one it got.
final class MacLink {
    private var browser: NWBrowser?
    private var transport: WireTransport?

    /// How long to give the local network before falling back. Bonjour on a
    /// network where the Mac *is* present resolves in well under a second.
    private static let bonjourTimeout: TimeInterval = 2
    /// How long the LAN path gets to produce a challenge and a sealed
    /// `ready` before we give up on it and punch instead.
    private static let lanHandshakeTimeout: TimeInterval = 5
    /// The punched path has already proved it carries packets by the time we
    /// hold a transport; this only waits out retransmission on a lossy link.
    private static let punchedHandshakeTimeout: TimeInterval = 15

    func cancel() {
        browser?.cancel()
        browser = nil
        transport?.close()
        transport = nil
    }

    /// Runs the full exchange. Local problems (unpaired, no path, impostor)
    /// surface as `failed` events so callers have one error path.
    func run(_ request: Wire.Request) -> AsyncStream<Wire.Event> {
        AsyncStream { continuation in
            guard let channelKey = try? PairingStore.channelKey() else {
                self.fail("This iPhone isn't paired with a Mac yet.", continuation)
                return
            }
            Task { @MainActor in
                // The LAN path first, but only on trial: finding the Mac
                // over Bonjour is not the same as being able to talk to it,
                // and until the conversation actually starts the punch stays
                // in reserve.
                if let endpoint = await self.bonjourEndpoint() {
                    let lan = TCPTransport(NWConnection(to: endpoint, using: .tcp))
                    self.transport = lan
                    if await self.exchange(
                        over: lan, channelKey: channelKey,
                        request: request, continuation: continuation,
                        deadline: Self.lanHandshakeTimeout, constrained: false
                    ) { return }
                    self.discard(lan)
                }
                switch await PunchClient.shared.open() {
                case let .success(punched):
                    self.transport = punched
                    if await self.exchange(
                        over: punched, channelKey: channelKey,
                        request: request, continuation: continuation,
                        deadline: Self.punchedHandshakeTimeout, constrained: true
                    ) { return }
                    self.discard(punched)
                    self.fail("Couldn't start a conversation with your Mac.", continuation)
                case let .failure(error):
                    self.fail(error.localizedDescription, continuation)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.cancel() }
            }
        }
    }

    /// Is the Mac visible on this network? Nil rather than an error: not
    /// finding it is the ordinary case away from home.
    @MainActor
    private func bonjourEndpoint() async -> NWEndpoint? {
        await withCheckedContinuation { cont in
            var settled = false
            let params = NWParameters()
            params.includePeerToPeer = true
            let browser = NWBrowser(
                for: .bonjour(type: Wire.bonjourType, domain: nil),
                using: params
            )
            let finish: (NWEndpoint?) -> Void = { endpoint in
                guard !settled else { return }
                settled = true
                browser.cancel()
                cont.resume(returning: endpoint)
            }
            browser.browseResultsChangedHandler = { results, _ in
                if let first = results.first?.endpoint { finish(first) }
            }
            browser.start(queue: .main)
            self.browser = browser
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.bonjourTimeout) { finish(nil) }
        }
    }

    /// Stops a transport we're abandoning from ever yielding into the stream
    /// the next attempt is about to use.
    @MainActor
    private func discard(_ transport: WireTransport) {
        transport.onBytes = nil
        transport.onClosed = nil
        transport.onSendProgress = nil
        transport.close()
        if self.transport === transport { self.transport = nil }
    }

    private func fail(_ message: String, _ continuation: AsyncStream<Wire.Event>.Continuation) {
        var e = Wire.Event(kind: "failed")
        e.text = message
        // This failure was made here, not received: the Mac never answered.
        e.local = true
        continuation.yield(e)
        continuation.yield(Wire.Event(kind: "done"))
        continuation.finish()
    }

    /// A transport that died with the answer still in flight. Distinct from
    /// `fail` because the two need opposite responses: a failure is a
    /// verdict to show, an interruption is a socket to rebuild — the
    /// overwhelmingly common cause is iOS suspending this app. No `done`
    /// follows, which is what tells the caller the turn is unfinished.
    private func interrupt(
        _ message: String?, _ continuation: AsyncStream<Wire.Event>.Continuation
    ) {
        var e = Wire.Event(kind: "interrupted")
        e.text = message
        continuation.yield(e)
        continuation.finish()
    }

    // MARK: - Handshake + streaming

    private enum Stage {
        case awaitingChallenge
        case awaitingReady(Wire.SecureChannel)
        case streaming(Wire.SecureChannel)
        /// The exchange ended on its own terms — the close that follows a
        /// clean `done` isn't the answer being cut off.
        case finished
    }

    /// Runs the handshake and, if it succeeds, streams the answer. Returns
    /// as soon as the outcome is decided: true once the Mac has proved
    /// itself and the request is away, false if it never got that far,
    /// leaving the caller free to try the other path.
    @MainActor
    private func exchange(
        over transport: WireTransport,
        channelKey: SymmetricKey,
        request: Wire.Request,
        continuation: AsyncStream<Wire.Event>.Continuation,
        deadline: TimeInterval,
        constrained: Bool
    ) async -> Bool {
        await withCheckedContinuation { decided in
            var settled = false
            let decide: (Bool) -> Void = { committed in
                guard !settled else { return }
                settled = true
                decided.resume(returning: committed)
            }
            self.handshake(
                over: transport, channelKey: channelKey,
                request: request, continuation: continuation,
                constrained: constrained, decide: decide
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + deadline) {
                decide(false)
            }
        }
    }

    private func handshake(
        over transport: WireTransport,
        channelKey: SymmetricKey,
        request: Wire.Request,
        continuation: AsyncStream<Wire.Event>.Continuation,
        constrained: Bool,
        decide: @escaping (Bool) -> Void
    ) {
        var framer = LineFramer()
        var stage = Stage.awaitingChallenge
        let clientNonce = Wire.Security.nonce()
        let deviceName = UIDevice.current.name

        func finish() {
            stage = .finished
            transport.close()
            continuation.finish()
        }

        func handle(_ frame: Data) {
            switch stage {
            case .finished:
                return

            case .awaitingChallenge:
                guard let event = try? JSONDecoder().decode(Wire.Event.self, from: frame),
                      event.kind == "challenge", let serverNonce = event.text
                else {
                    decide(true)
                    fail("Your Mac answered in a way this app doesn't understand.", continuation)
                    finish()
                    return
                }
                let auth = Wire.Auth(
                    name: deviceName,
                    nonce: clientNonce,
                    tag: Wire.Security.authTag(
                        channelKey: channelKey, serverNonce: serverNonce,
                        clientNonce: clientNonce, name: deviceName
                    ),
                    compress: true
                )
                guard var data = try? JSONEncoder().encode(auth) else { return }
                data.append(0x0A)
                transport.send(data)
                let sessionKey = Wire.Security.sessionKey(
                    channelKey: channelKey, serverNonce: serverNonce, clientNonce: clientNonce
                )
                stage = .awaitingReady(Wire.SecureChannel(key: sessionKey))

            case let .awaitingReady(channel):
                // Either the sealed `ready` (the Mac's proof of identity) or
                // a plain refusal.
                if let plain = channel.open(frame),
                   let event = try? JSONDecoder().decode(Wire.Event.self, from: plain),
                   event.kind == "ready" {
                    stage = .streaming(channel)
                    // Surface the capabilities to the caller before the
                    // answer, so screens can adapt.
                    continuation.yield(event)
                    // Shaping happens here and not earlier because only now
                    // is it known which path carries this: images get their
                    // smaller transit copy on the punched wire, where every
                    // kilobyte is seconds.
                    let outgoing = constrained ? request.thinned() : request
                    guard let payload = try? JSONEncoder().encode(outgoing) else { return }
                    let body = event.compress == true
                        ? Wire.Squeeze.pack(payload) : payload
                    guard let sealed = channel.seal(body) else { return }
                    transport.send(sealed)
                    decide(true)
                    return
                }
                if let event = try? JSONDecoder().decode(Wire.Event.self, from: frame),
                   event.kind == "failed" {
                    // The Mac refused us by name. Retrying on another path
                    // would only collect the same refusal.
                    decide(true)
                    continuation.yield(event)
                    continuation.yield(Wire.Event(kind: "done"))
                    finish()
                    return
                }
                decide(true)
                fail("Couldn't verify that this is your Mac. Try pairing again.", continuation)
                finish()

            case let .streaming(channel):
                guard let opened = channel.open(frame),
                      let plain = Wire.Squeeze.unpack(opened),
                      let event = try? JSONDecoder().decode(Wire.Event.self, from: plain)
                else {
                    interrupt("The connection to your Mac was interrupted.", continuation)
                    finish()
                    return
                }
                continuation.yield(event)
                if event.kind == "done" { finish() }
            }
        }

        transport.onBytes = { data in
            for frame in framer.push(data) { handle(frame) }
        }
        transport.onClosed = { [weak self] reason in
            if case .streaming = stage {
                stage = .finished
                self?.interrupt(reason, continuation)
            } else {
                decide(false)
            }
        }
        transport.start()
    }
}
