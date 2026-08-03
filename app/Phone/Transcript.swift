import SwiftUI

/// The conversation itself: parts, the turn's diffs, any error, and the
/// working indicator pinned to the bottom while the agent runs. Its own
/// view because the type checker gave up on it inline.
struct Transcript: View {
    let rows: [TurnPart]
    let diffs: [FileDiff]
    let error: String?
    let running: Bool
    let activity: String

    private static let indicatorID = "working"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // A ScrollView rather than a List: List draws separators
                // between rows, and a ruled transcript reads like a
                // spreadsheet. Structure here comes from space, alignment,
                // and weight — never from lines.
                LazyVStack(alignment: .leading, spacing: Space.betweenParts) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, part in
                        PartRow(part: part)
                            .id(index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !diffs.isEmpty {
                        ChangeSummary(diffs: diffs)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if running {
                        WorkingIndicator(activity: activity)
                            .id(Self.indicatorID)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.vertical, Space.betweenParts)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: rows.count) { scroll(proxy) }
            .onChange(of: running) { scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if running {
                proxy.scrollTo(Self.indicatorID, anchor: .bottom)
            } else if !rows.isEmpty {
                proxy.scrollTo(rows.count - 1, anchor: .bottom)
            }
        }
    }
}

/// What the turn changed. A tinted block rather than a ruled section —
/// same job a `Section` header did, done with surface instead of lines.
struct ChangeSummary: View {
    let diffs: [FileDiff]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Changes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(diffs, id: \.file) { diff in
                HStack(spacing: 8) {
                    Text(diff.file)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("+\(diff.additions ?? 0)")
                        .foregroundStyle(.green)
                    Text("−\(diff.deletions ?? 0)")
                        .foregroundStyle(.red)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

struct PartRow: View {
    let part: TurnPart

    var body: some View {
        switch part.type {
        case "user":
            Text(part.text ?? "")
                .padding(10)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case "text":
            // Full block-level markdown (see app/STYLEGUIDE.md for the
            // reading rhythm) — agents answer in markdown, always.
            MarkdownText(text: part.text ?? "")
        case "reasoning":
            Text(part.text ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
        case "tool":
            Label {
                Text(part.tool ?? "tool")
            } icon: {
                switch part.status {
                case "completed": Image(systemName: "checkmark.circle")
                case "error": Image(systemName: "xmark.circle")
                default: ProgressView().controlSize(.small)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}
