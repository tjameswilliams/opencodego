import SwiftUI

/// The list that appears above the composer when a message starts with "/".
///
/// Sits directly on top of the composer rather than in a sheet: picking a
/// command is part of writing the message, and a modal would take the
/// keyboard away mid-thought.
struct CommandPalette: View {
    let commands: [AgentCommand]
    let pick: (AgentCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(commands) { command in
                        Button {
                            pick(command)
                        } label: {
                            row(for: command)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func row(for command: AgentCommand) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("/\(command.name)")
                .font(.subheadline.monospaced().weight(.medium))
                .foregroundStyle(.primary)
            if let description = command.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            // A skill and a subtask behave differently enough from a plain
            // command to be worth one word each.
            if command.subtask == true {
                tag("subagent")
            } else if let source = command.source, source != "command" {
                tag(source)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}
