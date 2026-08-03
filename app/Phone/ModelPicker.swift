import SwiftUI

/// Pick the model this session's next turn runs on. Grouped by provider,
/// searchable, with the Mac's own default marked — because "whatever
/// OpenCode is configured to use" is a legitimate choice, not an absence of
/// one.
struct ModelPicker: View {
    @ObservedObject var store: ModelStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var grouped: [(provider: String, models: [AgentModel])] {
        let filtered = search.isEmpty ? store.models : store.models.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.provider.localizedCaseInsensitiveContains(search)
        }
        return Dictionary(grouping: filtered, by: \.provider)
            .map { (provider: $0.key, models: $0.value) }
            .sorted { $0.provider < $1.provider }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.selected = nil
                        dismiss()
                    } label: {
                        row(
                            title: "Use the Mac's default",
                            detail: store.models.first { $0.id == store.defaultID }?.name,
                            checked: store.selected == nil
                        )
                    }
                }
                ForEach(grouped, id: \.provider) { group in
                    Section(group.provider) {
                        ForEach(group.models) { model in
                            Button {
                                store.selected = model
                                dismiss()
                            } label: {
                                row(
                                    title: model.name,
                                    detail: badges(for: model),
                                    checked: store.selected?.id == model.id
                                )
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search models")
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if store.loading, store.models.isEmpty {
                    ProgressView("Asking your Mac…")
                } else if store.models.isEmpty {
                    ContentUnavailableView(
                        "No models configured",
                        systemImage: "cpu",
                        description: Text("Add a provider in OpenCode on your Mac.")
                    )
                }
            }
            .task { await store.loadIfNeeded() }
        }
    }

    private func badges(for model: AgentModel) -> String? {
        var parts: [String] = []
        if model.reasoning == true { parts.append("Reasoning") }
        if model.attachment == true { parts.append("Images") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func row(title: String, detail: String?, checked: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if checked {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
    }
}
