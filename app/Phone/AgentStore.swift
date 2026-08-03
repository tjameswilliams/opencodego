import GoKit
import SwiftUI

/// Which agent the session runs as.
///
/// The one that matters is `plan` — OpenCode describes it as "Plan mode.
/// Disallows all edit tools." That is the mode that makes steering from a
/// phone genuinely safe: you can explore, ask, and get a plan back with a
/// hard guarantee that nothing on disk changed. Choosing it is a stronger
/// promise than approving each edit, because there is nothing to approve.
@MainActor
final class AgentStore: ObservableObject {
    static let shared = AgentStore()

    @Published private(set) var agents: [AgentInfo] = []
    @Published var selected: AgentInfo? {
        didSet { UserDefaults.standard.set(selected?.name, forKey: Self.key) }
    }

    private static let key = "opencodego.agent"
    private var loading = false

    private init() {}

    /// Nil means "whatever OpenCode defaults to", which is `build`.
    var label: String { (selected?.name ?? "build").capitalized }

    /// True when the selected agent cannot write — worth saying out loud
    /// in the UI, because it changes what the whole screen means.
    var isReadOnly: Bool { selected?.name == "plan" }

    func loadIfNeeded() async {
        guard agents.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        for await event in MacLink().run(Wire.Request(kind: "agents")) {
            guard event.kind == "agents" else { continue }
            agents = event.agents ?? []
            if selected == nil, let remembered = UserDefaults.standard.string(forKey: Self.key) {
                selected = agents.first { $0.name == remembered }
            }
        }
    }
}
