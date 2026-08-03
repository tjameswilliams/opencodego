import SwiftUI

/// The prompt bar, following the shape Claude and ChatGPT have converged
/// on: one rounded container holding the text field, with a control row
/// beneath it — context controls (the model) on the left, actions (dictate,
/// send) on the right.
///
/// Circular 36pt buttons: the earlier inline icons sat under the 44pt touch
/// target and read small against the field.
struct Composer: View {
    @Binding var input: String
    let running: Bool
    @ObservedObject var dictation: Dictation
    /// What the model chip says. Nil hides the chip entirely — better than
    /// showing "Default" before the catalogue has loaded and then changing
    /// its mind under the user's thumb.
    let modelLabel: String?
    let onModel: () -> Void
    let onDictate: () -> Void
    let onSend: () -> Void

    private var empty: Bool {
        input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Send needs something to send; stop is always available while a turn
    /// runs.
    private var sendEnabled: Bool { running || !empty }

    var body: some View {
        VStack(spacing: 10) {
            TextField(
                dictation.recording ? "Listening…" : "Ask the agent…",
                text: $input, axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1 ... 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let modelLabel {
                    ModelChip(label: modelLabel, action: onModel)
                }
                Spacer(minLength: 8)
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
    }
}

/// The model selector: a capsule chip carrying the current model's name,
/// sized to match the circular buttons opposite it.
struct ModelChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model: \(label). Tap to change.")
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
