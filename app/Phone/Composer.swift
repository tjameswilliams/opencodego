import GoKit
import PhotosUI
import SwiftUI

/// The prompt bar, following the shape Claude and ChatGPT have converged
/// on: attachments strip, text field, then a control row — add-context and
/// model on the left, dictate and send on the right, all inside one rounded
/// container.
///
/// Circular 36pt controls: the earlier inline icons sat under the 44pt
/// touch target and read small against the field.
struct Composer: View {
    @Binding var input: String
    let running: Bool
    @ObservedObject var dictation: Dictation
    @ObservedObject var attachments: PromptAttachments
    @ObservedObject var models: ModelStore
    @ObservedObject var agents: AgentStore
    let onDictate: () -> Void
    let onSend: () -> Void

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var showingCamera = false

    private var empty: Bool {
        input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Send needs something to send — text or files; stop is always
    /// available while a turn runs.
    private var sendEnabled: Bool { running || !empty || !attachments.isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                AttachmentStrip(attachments: attachments)
            }

            TextField(
                dictation.recording ? "Listening…" : "Ask the agent…",
                text: $input, axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1 ... 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                addMenu
                // Always present, even before the catalogue arrives:
                // hiding it made a failed fetch look like a missing
                // feature, which is exactly how it was first reported.
                ModelMenu(models: models)
                if !agents.agents.isEmpty {
                    AgentMenu(agents: agents)
                }
                Spacer(minLength: 4)
                if !dictation.unavailable {
                    CircleButton(
                        systemName: dictation.recording ? "mic.fill" : "mic",
                        foreground: dictation.recording ? .white : .primary,
                        background: dictation.recording ? Color.red : Color.primary.opacity(0.08),
                        action: onDictate
                    )
                    .accessibilityLabel(dictation.recording ? "Stop dictation" : "Dictate")
                }
                CircleButton(
                    systemName: running ? "stop.fill" : "arrow.up",
                    foreground: sendEnabled ? .white : .secondary,
                    background: sendEnabled ? Color.accentColor : Color.primary.opacity(0.08),
                    action: onSend
                )
                .disabled(!sendEnabled)
                .accessibilityLabel(running ? "Stop the agent" : "Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.15), value: dictation.recording)
        .animation(.easeInOut(duration: 0.15), value: sendEnabled)
        .animation(.easeInOut(duration: 0.2), value: attachments.items.count)
        .photosPicker(
            isPresented: $showingPhotos, selection: $photoSelection,
            maxSelectionCount: 5, matching: .images
        )
        .onChange(of: photoSelection) {
            let picked = photoSelection
            photoSelection = []
            Task { await attachments.load(picked) }
        }
        .fileImporter(
            isPresented: $showingFiles, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            for url in urls { attachments.add(fileAt: url) }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in attachments.add(image: image) }
                .ignoresSafeArea()
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                showingPhotos = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            Button {
                showingFiles = true
            } label: {
                Label("Files", systemImage: "folder")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        // Menu tints its label with the accent colour; these are chrome,
        // not calls to action — the send button is the only accent here.
        .tint(.primary)
        .accessibilityLabel("Add files to the conversation")
    }
}

/// The model selector: a chip that opens a menu of what's configured,
/// grouped into a submenu per provider so a long catalogue stays usable.
struct ModelMenu: View {
    @ObservedObject var models: ModelStore

    private var byProvider: [(provider: String, models: [AgentModel])] {
        Dictionary(grouping: models.models, by: \.provider)
            .map { (provider: $0.key, models: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.provider < $1.provider }
    }

    var body: some View {
        Menu {
            if let error = models.error {
                Section(error) {
                    Button {
                        Task { await models.load() }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                }
            }
            Button {
                models.selected = nil
            } label: {
                Label(
                    "Mac's default",
                    systemImage: models.selected == nil ? "checkmark" : "desktopcomputer"
                )
            }
            // One flat list when it fits in a menu; providers as submenus
            // when it doesn't. Twelve is about where scrolling starts.
            if models.models.count <= 12 {
                ForEach(models.models) { model in
                    button(for: model)
                }
            } else {
                ForEach(byProvider, id: \.provider) { group in
                    Menu(group.provider) {
                        ForEach(group.models) { model in
                            button(for: model)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if models.loading, models.models.isEmpty {
                    ProgressView().controlSize(.mini)
                }
                Text(models.label).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .tint(.primary)
        .accessibilityLabel("Model: \(models.label). Tap to change.")
    }

    @ViewBuilder
    private func button(for model: AgentModel) -> some View {
        Button {
            models.selected = model
        } label: {
            if models.selected?.id == model.id {
                Label(model.name, systemImage: "checkmark")
            } else {
                Text(model.name)
            }
        }
    }
}

/// Which agent the turn runs as. Plan mode is the one that matters on a
/// phone — it cannot edit anything, so it is the only mode that is safe by
/// construction rather than by vigilance. Shown tinted when active,
/// because it changes what the whole screen means.
struct AgentMenu: View {
    @ObservedObject var agents: AgentStore

    var body: some View {
        Menu {
            ForEach(agents.agents) { agent in
                Button {
                    agents.selected = agent.name == "build" ? nil : agent
                } label: {
                    let chosen = (agents.selected?.name ?? "build") == agent.name
                    if chosen {
                        Label(agent.name.capitalized, systemImage: "checkmark")
                    } else {
                        Text(agent.name.capitalized)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if agents.isReadOnly {
                    Image(systemName: "eye")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(agents.label).lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(agents.isReadOnly ? Color.clay : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                Capsule().fill(agents.isReadOnly
                    ? Color.clay.opacity(0.15) : Color.primary.opacity(0.08))
            )
        }
        .tint(.primary)
        .accessibilityLabel("Agent: \(agents.label)")
    }
}

/// A 36pt circular control — comfortably tappable, visually weighted to
/// match the field it sits under.
struct CircleButton: View {
    let systemName: String
    let foreground: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 36, height: 36)
                .background(Circle().fill(background))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

/// UIKit's camera, wrapped — SwiftUI still has no native capture view.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
            dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            dismiss()
        }
    }
}
