import SwiftUI

// Throwaway: renders the REAL views from the app against mock state so the
// design can be checked without a paired Mac.

@main
struct HarnessApp: App {
    var body: some Scene { WindowGroup { HarnessView() } }
}

struct HarnessView: View {
    @State private var showPermission = false
    @State private var thinking = true

    private let thoughts = """
    The user wants the auth module refactored. Let me consider what that \
    actually involves before touching anything.

    First: AuthService owns both token refresh and session validation, which \
    is already two responsibilities. Splitting them would be cleaner but \
    changes the public surface.

    Second: the refresh path has a race — two concurrent 401s both trigger a \
    refresh. That is probably the real bug behind the reported symptom.

    I will read the file before proposing anything.
    """

    var body: some View {
        NavigationStack {
            Transcript(
                rows: [
                    TurnPart(type: "user", text: "Refactor the auth module"),
                    TurnPart(type: "reasoning", id: "r1", text: thoughts),
                    TurnPart(type: "tool", id: "t1", tool: "read", status: "completed"),
                    TurnPart(type: "text", id: "x1", text: """
                    Found it — the refresh path races. Here's the fix:

                    ```swift
                    actor TokenRefresher {
                        private var inFlight: Task<Token, Error>?
                        func token() async throws -> Token { try await (inFlight ?? start()).value }
                    }
                    ```

                    That serialises concurrent refreshes through one task.
                    """),
                    TurnPart(type: "user", text: "Good. Now run the tests"),
                    TurnPart(type: "reasoning", id: "r2", text: "Running the suite now."),
                ],
                diffs: [FileDiff(file: "Sources/Auth/AuthService.swift",
                                 additions: 24, deletions: 9, status: "modified")],
                error: nil, running: thinking, activity: "Running a command",
                turnStartedAt: Date().addingTimeInterval(-23)
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { BrandWordmark(height: 15) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(thinking ? "Settle" : "Think") { thinking.toggle() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ask") { showPermission = true }
                }
            }
            .sheet(isPresented: $showPermission) {
                PermissionSheet(request: PermissionRequest(
                    id: "p1", permission: "bash",
                    patterns: ["rm -rf build/ && npm publish --access public"],
                    always: ["rm *"], risk: "high"
                )) { _, _ in showPermission = false }
            }
        }
    }
}
