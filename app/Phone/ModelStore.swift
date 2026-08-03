import SwiftUI

/// The phone's model choice, and the catalogue it picks from.
///
/// The choice is remembered across launches but stays overridable per turn:
/// picking a model is the kind of decision people make once and then forget
/// about, right up until the moment they want something faster or smarter
/// for one specific question.
@MainActor
final class ModelStore: ObservableObject {
    static let shared = ModelStore()

    @Published private(set) var models: [AgentModel] = []
    /// What the Mac would use if we said nothing — shown as "Default" until
    /// the catalogue names it.
    @Published private(set) var defaultID: String?
    @Published private(set) var loading = false
    @Published var selected: AgentModel? {
        didSet {
            UserDefaults.standard.set(selected?.id, forKey: Self.key)
        }
    }

    private static let key = "opencodego.model"

    private init() {}

    /// What the composer's chip says.
    var label: String {
        if let selected { return selected.name }
        if let fallback = models.first(where: { $0.id == defaultID }) { return fallback.name }
        return "Default model"
    }

    /// Fetches the catalogue once per app run (models change when the user
    /// edits OpenCode's config, which is not a phone-session event).
    func loadIfNeeded() async {
        guard models.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        for await event in MacLink().run(Wire.Request(kind: "models")) {
            guard event.kind == "models" else { continue }
            models = event.models ?? []
            defaultID = event.defaultModel
            // Restore the remembered pick now that names exist to match it
            // against; a model that has since been removed from the config
            // silently falls back rather than failing a prompt later.
            if selected == nil, let remembered = UserDefaults.standard.string(forKey: Self.key) {
                selected = models.first { $0.id == remembered }
            }
        }
    }
}
