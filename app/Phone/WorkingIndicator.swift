import SwiftUI

/// "The agent is working" — and, where possible, what on.
///
/// A bare spinner would be a lie of omission here: an agent turn can run
/// for minutes, and the difference between "thinking", "reading a file",
/// and "waiting on you" is the whole reason to look at the phone. So the
/// label follows the stream, and the animation only signals liveness.
struct WorkingIndicator: View {
    /// What the agent is doing right now, in a few words.
    let activity: String

    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 10) {
            // Three dots breathing in sequence — quieter than a spinner
            // next to a wall of text, and it reads as "alive" rather than
            // "blocked".
            HStack(spacing: 4) {
                ForEach(0 ..< 3) { index in
                    Circle()
                        .frame(width: 6, height: 6)
                        .opacity(opacity(for: index))
                }
            }
            .foregroundStyle(.tint)

            Text(activity)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .padding(.vertical, 4)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 3
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent is working: \(activity)")
    }

    /// Each dot peaks a third of a cycle after the one before it.
    private func opacity(for index: Int) -> Double {
        let offset = (phase - Double(index)).truncatingRemainder(dividingBy: 3)
        let distance = min(offset, 3 - offset)
        return 0.25 + 0.75 * max(0, 1 - distance)
    }
}

extension TurnPart {
    /// This part rendered as a status line — what the working indicator
    /// says while it's the newest thing to have happened.
    var activityLabel: String? {
        switch type {
        case "reasoning": return "Thinking"
        case "tool":
            guard let tool else { return "Working" }
            // The tools people recognise get plain-English verbs; anything
            // else is named rather than guessed at.
            switch tool {
            case "read": return "Reading files"
            case "edit", "write", "patch": return "Editing files"
            case "bash": return "Running a command"
            case "glob", "grep", "find": return "Searching the project"
            case "webfetch", "websearch": return "Searching the web"
            case "task": return "Running a subagent"
            default: return tool.capitalized
            }
        case "text": return "Writing"
        default: return nil
        }
    }
}
