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
    @StateObject private var noFiles = PromptAttachments()
    @StateObject private var withFiles = PromptAttachments()
    @StateObject private var models = ModelStore.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Transcript sample") {
                        Text("Refactor the auth module")
                            .padding(10)
                            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        MarkdownText(text: "I'll start by reading the current implementation.\n\n- Check `AuthService`\n- Look for the token refresh path")
                        Label("read", systemImage: "checkmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Wordmark") {
                        BrandWordmark(height: 15)
                        BrandWordmark(height: 25)
                        BrandWordmark(height: 40, sweep: 0.45)
                    }
                    Section("Working indicator") {
                        WorkingIndicator(activity: "Running a command")
                        WorkingIndicator(activity: "Reading files",
                                         since: Date().addingTimeInterval(-25))
                        WorkingIndicator(activity: "Thinking",
                                         since: Date().addingTimeInterval(-50))
                    }
                }
                .listStyle(.plain)

                Divider()
                Text("Composer — empty").font(.caption).foregroundStyle(.secondary)
                Composer(
                    input: $empty, running: false, dictation: idle,
                    attachments: noFiles, models: models, onDictate: {}, onSend: {}
                )
                Text("Composer — typed, with attachments").font(.caption).foregroundStyle(.secondary)
                Composer(
                    input: $typed, running: false, dictation: idle,
                    attachments: withFiles, models: models, onDictate: {}, onSend: {}
                )
                Text("Composer — running").font(.caption).foregroundStyle(.secondary)
                Composer(
                    input: $empty, running: true, dictation: idle,
                    attachments: noFiles, models: models, onDictate: {}, onSend: {}
                )
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { BrandWordmark(height: 15) } }
            .task {
                models.mockForHarness()
                withFiles.add(image: swatch(.systemBlue), name: "screenshot.png")
                withFiles.add(image: swatch(.systemOrange), name: "diagram.jpg")
            }
        }
    }

    private func swatch(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
    }
}
