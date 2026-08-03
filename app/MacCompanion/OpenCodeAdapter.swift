import Foundation
import OSLog

/// The compatibility seam: mobile protocol v1 on one side, whatever OpenCode
/// version is installed on the other. Everything version-specific about
/// OpenCode's API lives in this file — endpoint paths, event names, JSON
/// shapes — so when OpenCode churns, this file changes and the phone app
/// doesn't. Verified against 1.18.10; docs/protocol-v1.md records the
/// contract and the skew already observed.
///
/// JSON is handled as dictionaries rather than Codable models on purpose:
/// the adapter's job is tolerating shape drift, and a typed decode that
/// throws on a renamed field is the opposite of that.
struct OpenCodeAdapter {
    let port: Int
    private let logger = Logger(subsystem: "com.timwilliams.opencodego", category: "adapter")

    private var base: String { "http://127.0.0.1:\(port)" }

    // MARK: - Plumbing

    private func get(_ path: String, directory: String? = nil) async throws -> Any {
        try await request(path, method: "GET", directory: directory, body: nil)
    }

    @discardableResult
    private func post(
        _ path: String, directory: String? = nil, body: [String: Any]? = [:]
    ) async throws -> Any {
        try await request(path, method: "POST", directory: directory, body: body)
    }

    private func request(
        _ path: String, method: String, directory: String?, body: [String: Any]?
    ) async throws -> Any {
        var components = URLComponents(string: base + path)!
        if let directory {
            components.queryItems = (components.queryItems ?? []) + [
                URLQueryItem(name: "directory", value: directory),
            ]
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AdapterError.http(path: path, body: String(text.prefix(300)))
        }
        // Some endpoints answer with nothing — prompt_async is a 204 —
        // and an empty body is success, not JSON to choke on.
        guard !data.isEmpty else { return NSNull() }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    enum AdapterError: LocalizedError {
        case http(path: String, body: String)
        var errorDescription: String? {
            switch self {
            case let .http(path, body): return "OpenCode \(path): \(body)"
            }
        }
    }

    // MARK: - v1: status / capabilities

    func health() async throws -> (healthy: Bool, version: String) {
        let json = try await get("/global/health") as? [String: Any] ?? [:]
        return (json["healthy"] as? Bool ?? false, json["version"] as? String ?? "unknown")
    }

    func capabilities() async throws -> Capabilities {
        let health = try await health()
        // Everything v1 needs exists on every server this adapter supports;
        // flags become meaningful the first time a version drops or gates
        // one of these.
        return Capabilities(
            opencodeVersion: health.version, permissions: true, questions: true, diffs: true
        )
    }

    /// The provider/model a prompt falls back to when the phone doesn't
    /// pick. The user's own configured default (`config.model`, as
    /// "provider/model") wins — it's the model their TUI uses, which is the
    /// least surprising choice a remote could make. Only failing that, the
    /// first provider default in *sorted* order: dictionary order once
    /// picked whatever it liked, including an image model.
    func defaultModel() async throws -> (providerID: String, modelID: String)? {
        if let config = try? await get("/config") as? [String: Any],
           let model = config["model"] as? String {
            let parts = model.split(separator: "/", maxSplits: 1)
            if parts.count == 2 { return (String(parts[0]), String(parts[1])) }
        }
        let json = try await get("/config/providers") as? [String: Any] ?? [:]
        let defaults = json["default"] as? [String: String] ?? [:]
        let providers = (json["providers"] as? [[String: Any]] ?? [])
            .compactMap { $0["id"] as? String }
            .sorted()
        for id in providers {
            if let model = defaults[id] { return (id, model) }
        }
        return nil
    }

    // MARK: - v1: projects / sessions

    func projects() async throws -> [Project] {
        let list = try await get("/project") as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let id = item["id"] as? String, id != "global",
                  let worktree = item["worktree"] as? String
            else { return nil }
            let time = item["time"] as? [String: Any]
            return Project(
                id: id,
                worktree: worktree,
                name: item["name"] as? String,
                updated: (time?["updated"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                known: true
            )
        }
        .sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
    }

    func sessions(limit: Int = 20) async throws -> [Session] {
        let list = try await get("/experimental/session?limit=\(limit)") as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let time = item["time"] as? [String: Any]
            return Session(
                id: id,
                title: item["title"] as? String,
                directory: item["directory"] as? String,
                updated: (time?["updated"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            )
        }
    }

    // MARK: - v1: prompt

    func createSession(directory: String) async throws -> String {
        let json = try await post("/session", directory: directory) as? [String: Any] ?? [:]
        guard let id = json["id"] as? String else {
            throw AdapterError.http(path: "/session", body: "no id in response")
        }
        return id
    }

    func promptAsync(
        sessionID: String, directory: String, text: String,
        providerID: String, modelID: String
    ) async throws {
        try await post(
            "/session/\(sessionID)/prompt_async", directory: directory,
            body: [
                "model": ["providerID": providerID, "modelID": modelID],
                "parts": [["type": "text", "text": text]],
            ]
        )
    }

    func abort(sessionID: String, directory: String) async throws {
        try await post("/session/\(sessionID)/abort", directory: directory)
    }

    // MARK: - v1: permission

    /// Pending asks, straight from the poll endpoint — the recovery path
    /// when an event was missed (or the phone just woke from a push).
    func pendingPermissions(directory: String) async throws -> [PermissionRequest] {
        let list = try await get("/permission", directory: directory) as? [[String: Any]] ?? []
        return list.compactMap(Self.permission(from:))
    }

    func replyPermission(id: String, directory: String, reply: String) async throws {
        try await post(
            "/permission/\(id)/reply", directory: directory, body: ["reply": reply]
        )
    }

    // MARK: - v1: question

    func pendingQuestions(directory: String) async throws -> [QuestionRequest] {
        let list = try await get("/question", directory: directory) as? [[String: Any]] ?? []
        return list.compactMap(Self.question(from:))
    }

    func replyQuestion(id: String, directory: String, answers: [[String]]) async throws {
        try await post(
            "/question/\(id)/reply", directory: directory, body: ["answers": answers]
        )
    }

    // MARK: - v1: transcript + diff

    /// The durable per-turn diffs: user messages carry what their turn
    /// changed (`info.summary.diffs`).
    func turnDiffs(sessionID: String, directory: String) async throws -> [FileDiff] {
        let messages = try await get(
            "/session/\(sessionID)/message", directory: directory
        ) as? [[String: Any]] ?? []
        return messages.flatMap { message -> [FileDiff] in
            let info = message["info"] as? [String: Any]
            let summary = info?["summary"] as? [String: Any]
            let diffs = summary?["diffs"] as? [[String: Any]] ?? []
            return diffs.compactMap { d in
                guard let file = d["file"] as? String else { return nil }
                return FileDiff(
                    file: file,
                    patch: d["patch"] as? String,
                    additions: d["additions"] as? Int,
                    deletions: d["deletions"] as? Int,
                    status: d["status"] as? String
                )
            }
        }
    }

    /// Transcript flattened to protocol parts, for continuing a session.
    func transcript(sessionID: String, directory: String) async throws -> [TurnPart] {
        let messages = try await get(
            "/session/\(sessionID)/message", directory: directory
        ) as? [[String: Any]] ?? []
        return messages.flatMap { message -> [TurnPart] in
            let info = message["info"] as? [String: Any]
            let role = info?["role"] as? String ?? "assistant"
            let parts = message["parts"] as? [[String: Any]] ?? []
            return parts.compactMap { part in
                Self.turnPart(from: part, role: role)
            }
        }
    }

    // MARK: - v1: event stream

    /// The instance's SSE feed as parsed dictionaries. One subscription per
    /// running turn is fine at this scale; consolidating to a single global
    /// subscription is an optimization for later.
    func events(directory: String) -> AsyncThrowingStream<[String: Any], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var components = URLComponents(string: base + "/event")!
                components.queryItems = [URLQueryItem(name: "directory", value: directory)]
                let (bytes, _) = try await URLSession.shared.bytes(from: components.url!)
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: "),
                          let data = line.dropFirst(6).data(using: .utf8),
                          let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - OpenCode → v1 mapping

    /// `permission.asked` (1.18+) carries the request at `properties`;
    /// 1.16-era `permission.updated` did too. Both funnel here.
    static func permission(from json: [String: Any]) -> PermissionRequest? {
        // Some versions nest under "request".
        let body = (json["request"] as? [String: Any]) ?? json
        guard let id = body["id"] as? String else { return nil }
        var patterns = body["patterns"] as? [String] ?? []
        if patterns.isEmpty, let metadata = body["metadata"] as? [String: Any],
           let command = metadata["command"] as? String {
            patterns = [command]
        }
        return PermissionRequest(
            id: id,
            sessionID: body["sessionID"] as? String,
            permission: body["permission"] as? String ?? body["type"] as? String,
            patterns: patterns,
            always: body["always"] as? [String]
        )
    }

    /// A question request, from the poll endpoint or a `question.asked`
    /// event's properties (some versions nest under "request").
    static func question(from json: [String: Any]) -> QuestionRequest? {
        let body = (json["request"] as? [String: Any]) ?? json
        guard let id = body["id"] as? String,
              let rawQuestions = body["questions"] as? [[String: Any]]
        else { return nil }
        let items = rawQuestions.compactMap { q -> QuestionItem? in
            guard let question = q["question"] as? String else { return nil }
            let options = (q["options"] as? [[String: Any]] ?? []).compactMap { o -> QuestionOption? in
                guard let label = o["label"] as? String else { return nil }
                return QuestionOption(label: label, description: o["description"] as? String)
            }
            return QuestionItem(
                question: question,
                header: q["header"] as? String,
                options: options,
                multiple: q["multiple"] as? Bool,
                custom: q["custom"] as? Bool
            )
        }
        guard !items.isEmpty else { return nil }
        return QuestionRequest(id: id, sessionID: body["sessionID"] as? String, questions: items)
    }

    /// An OpenCode message part → the phone's TurnPart, or nil for part
    /// types the phone doesn't render.
    static func turnPart(from part: [String: Any], role: String) -> TurnPart? {
        guard let type = part["type"] as? String else { return nil }
        let id = part["id"] as? String
        switch type {
        case "text":
            // The user's own words come back as role "user" — the phone
            // already has them, but a resumed/continued session needs them
            // to rebuild the conversation.
            return TurnPart(
                type: role == "user" ? "user" : "text", id: id, text: part["text"] as? String
            )
        case "reasoning":
            return TurnPart(type: "reasoning", id: id, text: part["text"] as? String)
        case "tool":
            let state = part["state"] as? [String: Any]
            return TurnPart(
                type: "tool", id: id,
                tool: part["tool"] as? String,
                status: state?["status"] as? String
            )
        default:
            // step-start/step-finish/patch and future kinds: nothing the
            // phone renders yet.
            return nil
        }
    }
}
