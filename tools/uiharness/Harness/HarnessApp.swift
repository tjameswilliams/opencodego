import SwiftUI

// Throwaway: renders the REAL Composer and WorkingIndicator from the app
// against mock state so the design can be checked without a paired Mac.

@main
struct HarnessApp: App {
    var body: some Scene {
        WindowGroup { HarnessView() }
    }
}

struct HarnessView: View {
    @State private var empty = ""
    @State private var typed = "Add a docstring to the greet function and run the tests"
    @StateObject private var idle = Dictation()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Transcript sample") {
                        Text("Refactor the auth module")
                            .padding(10)
                            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        MarkdownText(text: "I'll start by reading the current implementation.\n\n- Check `AuthService`\n- Look for the token refresh path\n\nThen I'll propose a change.")
                        Label("read", systemImage: "checkmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Working indicator") {
                        WorkingIndicator(activity: "Thinking")
                        WorkingIndicator(activity: "Running a command")
                        WorkingIndicator(activity: "Reading files")
                    }
                }
                .listStyle(.plain)

                Divider()
                Text("Composer — empty").font(.caption).foregroundStyle(.secondary)
                Composer(input: $empty, running: false, dictation: idle, onDictate: {}, onSend: {})
                Text("Composer — typed").font(.caption).foregroundStyle(.secondary)
                Composer(input: $typed, running: false, dictation: idle, onDictate: {}, onSend: {})
                Text("Composer — running").font(.caption).foregroundStyle(.secondary)
                Composer(input: $empty, running: true, dictation: idle, onDictate: {}, onSend: {})
            }
            .navigationTitle("opencodego")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
