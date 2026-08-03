import SwiftUI

@main
struct PhoneApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) {
            // iOS suspended our socket while we were away, and the NAT
            // mapping behind the remembered punch endpoint has probably
            // lapsed with it. Dropping it turns a stale path into a quick
            // re-verify instead of a mysterious timeout.
            if scenePhase == .active { PunchClient.shared.invalidate() }
        }
    }
}

/// Pairing is the front door: an unpaired phone can do nothing else, and a
/// paired one should never see the pairing screen again.
struct RootView: View {
    @State private var paired = PairingStore.load() != nil

    var body: some View {
        Group {
            if paired {
                HomeView()
            } else {
                PairingGate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: PairingStore.changed)) { _ in
            paired = PairingStore.load() != nil
        }
    }
}

struct PairingGate: View {
    @StateObject private var session = PairingSession()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("OpenCode Go")
                .font(.largeTitle.bold())
            Text("Your Mac writes the code. Your phone holds the leash.")
                .foregroundStyle(.secondary)
            PairingPhaseView(session: session)
            Spacer()
        }
        .padding()
    }
}
