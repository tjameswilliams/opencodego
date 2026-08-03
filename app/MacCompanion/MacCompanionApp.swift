import Sparkle
import SwiftUI

/// The Mac companion: a menu bar item and nothing else. Its jobs — keep
/// `opencode serve` alive on localhost, serve the paired phone over the
/// authenticated channel, and give pairing a window to happen in.
@main
struct MacCompanionApp: App {
    @StateObject private var opencode = OpenCodeProcess()
    @StateObject private var phone = PhoneLinkMonitor.shared
    @State private var server: GoServer?
    /// Sparkle drives its own update checks against the appcast; this also
    /// backs the menu's manual "Check for Updates…". The app is distributed
    /// outside the App Store (brew cask / direct dmg), so updating is ours
    /// to do.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        MenuBarExtra("OpenCode Go", systemImage: menuSymbol) {
            StatusMenu(opencode: opencode, phone: phone, server: server, updater: updater)
                .onAppear(perform: bootstrap)
        }

        Window("Devices", id: "devices") {
            DevicesWindow()
        }
        .windowResizability(.contentSize)
    }

    private var menuSymbol: String {
        switch opencode.state {
        case .running: return "iphone.gen3.radiowaves.left.and.right"
        case .starting: return "ellipsis.circle"
        case .stopped, .failed: return "exclamationmark.circle"
        }
    }

    private func bootstrap() {
        guard server == nil else { return }
        opencode.start()
        let server = GoServer(adapter: { [weak opencode] in
            guard case let .running(port, _) = opencode?.state else { return nil }
            return OpenCodeAdapter(port: port)
        })
        server.start()
        self.server = server
    }
}

struct StatusMenu: View {
    @ObservedObject var opencode: OpenCodeProcess
    @ObservedObject var phone: PhoneLinkMonitor
    var server: GoServer?
    var updater: SPUStandardUpdaterController?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch opencode.state {
            case let .running(port, version):
                Text("OpenCode \(version) · port \(String(port))")
            case .starting:
                Text("Starting OpenCode…")
            case .stopped:
                Text("OpenCode stopped")
            case let .failed(message):
                Text(message)
            }
            if let name = phone.connectedName {
                Text("\(name) connected")
            } else if PairingStore.load() != nil {
                Text("Phone not connected")
            }
            Divider()
            Button(PairingStore.load() == nil ? "Pair iPhone…" : "Devices…") {
                openWindow(id: "devices")
                NSApp.activate(ignoringOtherApps: true)
            }
            if let server {
                // The kill switch: paused means the Mac stops advertising
                // and listening on both paths — not merely refusing.
                Button(server.paused ? "Resume Remote Access" : "Pause Remote Access") {
                    server.setPaused(!server.paused)
                }
            }
            Divider()
            if let updater {
                Button("Check for Updates…") { updater.checkForUpdates(nil) }
            }
            Button("Quit") {
                opencode.stop()
                NSApp.terminate(nil)
            }
        }
    }
}

struct DevicesWindow: View {
    @StateObject private var pairing = PairingSession()
    @StateObject private var phone = PhoneLinkMonitor.shared
    @State private var paired = PairingStore.load()
    @State private var confirmingRevoke = false

    var body: some View {
        VStack(spacing: 16) {
            if let paired {
                Image(systemName: "iphone.gen3")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text(paired.name).font(.headline)
                Group {
                    if let name = phone.connectedName {
                        Label("\(name) connected now", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Paired \(paired.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)

                Text("Revoking removes this Mac's trust in that iPhone. It can no longer connect, see your projects, or approve anything — and the rendezvous records are wiped so a future pairing starts clean.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)

                Button("Revoke This Device", role: .destructive) { confirmingRevoke = true }
                    .confirmationDialog(
                        "Revoke \(paired.name)?",
                        isPresented: $confirmingRevoke, titleVisibility: .visible
                    ) {
                        Button("Revoke", role: .destructive) {
                            pairing.unpair()
                            self.paired = nil
                        }
                    } message: {
                        Text("You'll need to pair again from both devices to reconnect.")
                    }
            } else {
                PairingPhaseView(session: pairing)
            }
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 340)
        .onReceive(NotificationCenter.default.publisher(for: PairingStore.changed)) { _ in
            paired = PairingStore.load()
        }
    }
}
