import Foundation

/// The phone-facing shapes of mobile protocol v1. These deliberately do NOT
/// mirror OpenCode's API models — the Mac adapter maps whatever the
/// installed OpenCode version returns into these, and the phone is coupled
/// only to this file. Fields are optional wherever a future Mac might
/// reasonably omit them; the phone must render around absence, not crash.
/// See docs/protocol-v1.md for the verified OpenCode calls behind each.

/// What this Mac's OpenCode installation can do — sent on `ready`, so the
/// phone can enable or hide features before asking for anything.
public struct Capabilities: Codable, Equatable, Sendable {
    public var opencodeVersion: String?
    public var permissions: Bool?
    public var questions: Bool?
    public var diffs: Bool?

    public init(
        opencodeVersion: String? = nil, permissions: Bool? = nil,
        questions: Bool? = nil, diffs: Bool? = nil
    ) {
        self.opencodeVersion = opencodeVersion
        self.permissions = permissions
        self.questions = questions
        self.diffs = diffs
    }
}

/// A place the agent can work: a project OpenCode has opened before, or a
/// git repo the Mac companion discovered that OpenCode hasn't seen yet
/// (`known == false`) — the launcher offers both.
public struct Project: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// Absolute path on the Mac. Displayed by its last component; the full
    /// path is detail, not identity, on a phone screen.
    public var worktree: String
    public var name: String?
    public var updated: Date?
    /// False for discovered-but-never-opened repos.
    public var known: Bool?

    public init(
        id: String, worktree: String, name: String? = nil,
        updated: Date? = nil, known: Bool? = nil
    ) {
        self.id = id
        self.worktree = worktree
        self.name = name
        self.updated = updated
        self.known = known
    }

    public var displayName: String {
        name ?? worktree.split(separator: "/").last.map(String.init) ?? worktree
    }
}

/// One OpenCode session — a thread the user can continue from the phone.
public struct Session: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    /// The project worktree it belongs to.
    public var directory: String?
    public var updated: Date?

    public init(id: String, title: String? = nil, directory: String? = nil, updated: Date? = nil) {
        self.id = id
        self.title = title
        self.directory = directory
        self.updated = updated
    }
}

/// The agent wants to do something and is blocked until someone answers.
/// This is the object the approval sheet renders — everything the user
/// needs to decide is here, because fetching more mid-decision is exactly
/// the round trip a phone can't afford.
public struct PermissionRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sessionID: String?
    /// What class of thing: "bash", "edit", …
    public var permission: String?
    /// The concrete ask, e.g. the exact command.
    public var patterns: [String]?
    /// What an "always" reply would whitelist — shown so "always allow"
    /// is an informed choice, not a mystery toggle.
    public var always: [String]?

    public init(
        id: String, sessionID: String? = nil, permission: String? = nil,
        patterns: [String]? = nil, always: [String]? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.permission = permission
        self.patterns = patterns
        self.always = always
    }
}

/// The agent is asking the user something — distinct from a permission:
/// there's nothing to allow, just a decision only the user can make.
public struct QuestionRequest: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var sessionID: String?
    public var questions: [QuestionItem]

    public init(id: String, sessionID: String? = nil, questions: [QuestionItem]) {
        self.id = id
        self.sessionID = sessionID
        self.questions = questions
    }
}

public struct QuestionItem: Codable, Hashable, Sendable {
    public var question: String
    /// Very short label (chip-sized).
    public var header: String?
    public var options: [QuestionOption]
    public var multiple: Bool?
    /// True when a free-text answer is allowed alongside the options.
    public var custom: Bool?

    public init(
        question: String, header: String? = nil, options: [QuestionOption],
        multiple: Bool? = nil, custom: Bool? = nil
    ) {
        self.question = question
        self.header = header
        self.options = options
        self.multiple = multiple
        self.custom = custom
    }
}

public struct QuestionOption: Codable, Hashable, Sendable {
    public var label: String
    public var description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

/// One file's worth of change from a turn, as a unified patch — the review
/// screen's unit.
public struct FileDiff: Codable, Equatable, Sendable {
    public var file: String
    public var patch: String?
    public var additions: Int?
    public var deletions: Int?
    /// "modified" | "added" | "deleted"
    public var status: String?

    public init(
        file: String, patch: String? = nil, additions: Int? = nil,
        deletions: Int? = nil, status: String? = nil
    ) {
        self.file = file
        self.patch = patch
        self.additions = additions
        self.deletions = deletions
        self.status = status
    }
}

/// One streaming piece of a running turn. Flattened from OpenCode's
/// message-part events into the little the phone actually renders; `type`
/// mirrors OpenCode's part types ("text", "reasoning", "tool", "step-start",
/// "step-finish", "patch") without promising the phone all of them.
public struct TurnPart: Codable, Equatable, Sendable {
    public var type: String
    /// The part's stable id, so a replayed or re-sent snapshot updates in
    /// place instead of appending a duplicate.
    public var id: String?
    /// text/reasoning: the accumulated content so far.
    public var text: String?
    /// tool: which tool.
    public var tool: String?
    /// tool: "pending" | "running" | "completed" | "error".
    public var status: String?

    public init(
        type: String, id: String? = nil, text: String? = nil,
        tool: String? = nil, status: String? = nil
    ) {
        self.type = type
        self.id = id
        self.text = text
        self.tool = tool
        self.status = status
    }
}
