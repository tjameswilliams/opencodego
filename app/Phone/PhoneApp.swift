import SwiftUI

@main
struct PhoneApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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
