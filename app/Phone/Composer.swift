import SwiftUI

/// The prompt bar, following the shape Claude and ChatGPT have converged
/// on: one rounded container holding the field, with the controls on their
/// own row beneath it. Circular 36pt buttons — the previous inline icons
/// were below the 44pt touch target and read as small next to the field.
struct Composer: View {
    @Binding var input: String
    let running: Bool
    @ObservedObject var dictation: Dictation
    let onDictate: () -> Void
    let onSend: () -> Void

    @FocusState private var focused: Bool

    private var empty: Bool {
        input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Send is only meaningful with something to send; while a turn runs
    /// the same button becomes stop, which is always available.
    private var sendEnabled: Bool { running || !empty }

    var body: some View {
        VStack(spacing: 10) {
            TextField(
                dictation.recording ? "Listening…" : "Ask the agent…",
                text: $input, axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1 ... 6)
            .focused($focused)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Spacer()
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.15), value: dictation.recording)
        .animation(.easeInOut(duration: 0.15), value: sendEnabled)
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
