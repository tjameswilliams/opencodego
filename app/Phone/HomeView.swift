import SwiftUI

/// The launcher: recent sessions to continue, projects to start fresh in.
/// Both lists come from the Mac in one round trip each; pull-to-refresh
/// re-asks. Errors render inline where the list would be — on a phone,
/// away from home, "couldn't reach your Mac" IS the content.
struct HomeView: View {
    @State private var projects: [Project] = []
    @State private var sessions: [Session] = []
    @State private var error: String?
    @State private var loading = false
    /// Nil = unknown/checking, true = a path to the Mac exists right now.
    @State private var reachable: Bool?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                    }
                }
                if !sessions.isEmpty {
                    Section("Continue") {
                        ForEach(sessions) { session in
                            NavigationLink(value: Destination.session(session)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title ?? "Untitled session")
                                        .lineLimit(1)
                                    if let directory = session.directory {
                                        Text(directory.split(separator: "/").last.map(String.init) ?? directory)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if !projects.isEmpty {
                    Section("Projects") {
                        ForEach(projects) { project in
                            NavigationLink(value: Destination.project(project)) {
                                Text(project.displayName)
                            }
                        }
                    }
                }
            }
            .navigationTitle("OpenCode Go")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // The standing answer to "is my Mac in reach?" — probed
                    // over the punched path, which is the only honest test:
                    // it proves packets travel, from home or anywhere.
                    Circle()
                        .fill(reachable == true ? .green : reachable == false ? .red : .gray)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(
                            reachable == true ? "Mac connected"
                                : reachable == false ? "Mac unreachable" : "Checking"
                        )
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case let .session(session):
                    SessionView(
                        project: session.directory ?? "", session: session.id,
                        title: session.title ?? "Session"
                    )
                case let .project(project):
                    SessionView(
                        project: project.worktree, session: nil,
                        title: project.displayName
                    )
                }
            }
            .overlay {
                if loading, sessions.isEmpty, projects.isEmpty {
                    ProgressView("Reaching your Mac…")
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private enum Destination: Hashable {
        case session(Session)
        case project(Project)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        error = nil
        // Probe alongside the lists, not before them — the lists are their
        // own proof of reach when they arrive, and a successful probe
        // leaves a proven punch path for the next request to reuse.
        Task { reachable = await PunchClient.shared.reachable().isSuccess }
        // Two independent one-shot requests; each failure surfaces once.
        for kind in ["sessions", "projects"] {
            for await event in MacLink().run(Wire.Request(kind: kind)) {
                switch event.kind {
                case "sessions": sessions = event.sessions ?? []
                case "projects": projects = event.projects ?? []
                case "failed": error = event.text
                default: break
                }
            }
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
