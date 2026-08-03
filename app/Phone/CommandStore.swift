import SwiftUI

/// The slash commands this Mac's OpenCode offers.
///
/// Fetched, never hardcoded: the list includes whatever the user has
/// written into `.opencode/command/*.md`, plus skills and MCP prompts, and
/// it changes when they edit their config. A built-in list would be wrong
/// on the first machine that isn't the developer's.
@MainActor
final class CommandStore: ObservableObject {
    static let shared = CommandStore()

    @Published private(set) var commands: [AgentCommand] = []
    @Published private(set) var loading = false
    /// Absent silently: an OpenCode without commands, or a companion too
    /// old to answer, should cost the user a palette — not an error.
    @Published private(set) var available = true

    private init() {}

    func loadIfNeeded() async {
        guard commands.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        for await event in MacLink().run(Wire.Request(kind: "commands")) {
            if event.kind == "failed" { available = false }
            guard event.kind == "commands" else { continue }
            commands = event.commands ?? []
            available = true
        }
    }

    /// Commands matching what's been typed after the slash. Prefix matches
    /// first — someone typing "/re" means `/review`, not the command whose
    /// description happens to contain "re".
    func matching(_ query: String) -> [AgentCommand] {
        guard !query.isEmpty else { return commands }
        let needle = query.lowercased()
        let prefix = commands.filter { $0.name.lowercased().hasPrefix(needle) }
        let rest = commands.filter {
            !$0.name.lowercased().hasPrefix(needle) &&
                ($0.name.lowercased().contains(needle)
                    || ($0.description ?? "").lowercased().contains(needle))
        }
        return prefix + rest
    }
}

/// What the composer has typed, understood as a possible slash command.
///
/// Kept as a parsing function rather than state so there is exactly one
/// definition of "is this a command" shared by the palette and the send
/// path — the classic way these two drift apart is two parsers.
enum SlashInput {
    /// The command to run, but only when the name is one this Mac actually
    /// has. Everything else is prose, including:
    ///
    /// - a typo (`/sumarize`), which OpenCode answers with an opaque 500
    /// - a path (`/Users/tim/thing.swift — look at this`), which would
    ///   otherwise parse as a command named "Users"
    ///
    /// Checking against the real list is what makes both harmless. The
    /// palette gives feedback while typing, so a typo is visible before
    /// send rather than after.
    static func command(_ text: String, known: [AgentCommand]) -> (name: String, arguments: String)? {
        guard let parsed = parse(text) else { return nil }
        guard known.contains(where: { $0.name == parsed.name }) else { return nil }
        return parsed
    }

    /// The raw split, regardless of whether the name is real.
    static func parse(_ text: String) -> (name: String, arguments: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), trimmed.count > 1 else { return nil }
        let body = trimmed.dropFirst()
        guard let space = body.firstIndex(where: { $0 == " " || $0 == "\n" }) else {
            return (String(body), "")
        }
        return (
            String(body[body.startIndex ..< space]),
            String(body[space...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// While the user is still typing the *name* — no space yet — the
    /// palette should be open and filtering. Once they've typed a space
    /// they're writing arguments, and the palette gets out of the way.
    static func query(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let body = trimmed.dropFirst()
        guard !body.contains(" "), !body.contains("\n") else { return nil }
        return String(body)
    }
}
