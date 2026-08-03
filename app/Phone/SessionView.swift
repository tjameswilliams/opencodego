import SwiftUI

/// One conversation with the agent: prompt at the bottom, the turn
/// streaming above it, approvals as a sheet the moment the agent blocks.
///
/// Reconnection is the design center, not an edge case: every event of a
/// turn is counted, and when the socket dies mid-answer (backgrounding the
/// app is enough) the view resumes the same turn from that count when it
/// returns — the Mac replays what was missed and streams on. See LiveTurns
/// on the Mac side.
struct SessionView: View {
    let project: String
    @State var session: String?
    let title: String

    /// The transcript as the phone renders it: parts keyed by id so a
    /// re-sent snapshot updates in place instead of duplicating.
    @State private var rows: [TurnPart] = []
    @State private var diffs: [FileDiff] = []
    @State private var input = ""
    @State private var running = false
    @State private var error: String?
    @State private var permission: PermissionRequest?
    @State private var question: QuestionRequest?

    /// The in-flight turn: its phone-minted id and how many of its events
    /// arrived — exactly what `resume` needs.
    @State private var turnID: String?
    @State private var cursor = 0
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dictation = Dictation()
    @ObservedObject private var models = ModelStore.shared
    @ObservedObject private var commands = CommandStore.shared
    @StateObject private var attachments = PromptAttachments()
    /// What was typed before dictation started, so speech appends to it
    /// rather than eating it.
    @State private var typedBeforeDictation = ""

    init(project: String, session: String?, title: String) {
        self.project = project
        _session = State(initialValue: session)
        self.title = title
    }

    /// What to say the agent is doing: the newest part that has an opinion,
    /// falling back to the honest generic while the first tokens are still
    /// in flight.
    private var activity: String {
        rows.reversed().compactMap(\.activityLabel).first ?? "Working"
    }

    /// Commands to offer right now, or nil when the user isn't typing one.
    private var paletteMatches: [AgentCommand]? {
        guard let query = SlashInput.query(input) else { return nil }
        return commands.matching(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            Transcript(
                rows: rows, diffs: diffs, error: error,
                running: running, activity: activity
            )
            if let matches = paletteMatches {
                CommandPalette(commands: matches) { command in
                    // Leave a trailing space when the command wants
                    // arguments, so the caret is where typing continues.
                    input = "/\(command.name)" + (command.takesArguments ? " " : "")
                }
            }
            Composer(
                input: $input,
                running: running,
                dictation: dictation,
                attachments: attachments,
                models: models,
                onDictate: {
                    if !dictation.recording { typedBeforeDictation = input }
                    dictation.toggle()
                },
                onSend: { running ? abort() : send() }
            )
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $permission) { request in
            PermissionSheet(request: request) { reply in
                answer(request, reply: reply)
            }
        }
        .sheet(item: $question) { request in
            QuestionSheet(request: request) { answers in
                question = nil
                var wire = Wire.Request(kind: "question")
                wire.questionID = request.id
                wire.project = project
                wire.answers = answers
                Task {
                    for await event in MacLink().run(wire) where event.kind == "failed" {
                        error = event.text
                    }
                }
            }
        }
        .onChange(of: attachments.error) {
            if let message = attachments.error { error = message }
        }
        .task {
            if session != nil { await loadTranscript() }
        }
        .task { await models.loadIfNeeded() }
        .task { await commands.loadIfNeeded() }
        .animation(.easeOut(duration: 0.15), value: paletteMatches?.count)
        .onChange(of: scenePhase) {
            // Back on screen with a turn unfinished: the socket is dead
            // (iOS killed it), the Mac's work isn't. Pick the turn back up.
            if scenePhase == .active, running { resume() }
            // Leaving with the mic live would keep recording off-screen.
            if scenePhase != .active { dictation.stop() }
        }
        .onChange(of: dictation.transcript) {
            guard !dictation.transcript.isEmpty else { return }
            let prefix = typedBeforeDictation.isEmpty ? "" : typedBeforeDictation + " "
            input = prefix + dictation.transcript
        }
        .onChange(of: dictation.error) {
            if let message = dictation.error { error = message }
        }
    }

    // MARK: - Turn lifecycle

    private func send() {
        guard !running else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Files alone are a legitimate prompt ("look at this"), but the
        // model does better with a nudge than with nothing at all.
        let files = attachments.wireAttachments()
        guard !text.isEmpty || !files.isEmpty else { return }
        let prompt = text.isEmpty ? "Take a look at the attached file(s)." : text
        // Order matters: stop the recogniser and drop its transcript before
        // clearing, or its next partial result refills the field.
        dictation.reset()
        typedBeforeDictation = ""
        input = ""
        error = nil
        diffs = []
        // Name the files in the transcript so the turn reads correctly
        // later, when the thumbnails are long gone.
        let names = attachments.items.map(\.name)
        attachments.clear()
        rows.append(TurnPart(
            type: "user",
            text: names.isEmpty ? prompt : prompt + "\n\n📎 " + names.joined(separator: ", ")
        ))

        var request = Wire.Request(kind: "prompt")
        request.project = project
        request.session = session
        request.attachments = files.isEmpty ? nil : files
        if let slash = SlashInput.command(prompt, known: commands.commands) {
            // The Mac invokes the command by name; OpenCode expands its own
            // template. Nothing here knows what the command actually says.
            request.command = slash.name
            request.arguments = slash.arguments
        } else {
            request.text = prompt
        }
        // Absent means "whatever the Mac would have used" — a deliberate
        // choice the picker offers explicitly.
        request.providerID = models.selected?.providerID
        request.modelID = models.selected?.modelID
        let id = UUID().uuidString
        request.turn = id
        turnID = id
        cursor = 0
        running = true
        Task { await consume(MacLink().run(request)) }
    }

    private func resume() {
        guard let turnID else { return }
        var request = Wire.Request(kind: "resume")
        request.turn = turnID
        request.from = cursor
        Task { await consume(MacLink().run(request)) }
    }

    /// Stops the agent, not just the stream: the Mac tells OpenCode to
    /// abort the session, and the running turn winds down through its own
    /// idle → done, which is what resets `running` honestly.
    private func abort() {
        guard let session else { running = false; turnID = nil; return }
        var request = Wire.Request(kind: "abort")
        request.session = session
        request.project = project
        Task {
            for await event in MacLink().run(request) where event.kind == "failed" {
                error = event.text
            }
        }
    }

    /// One event loop for prompt and resume alike — the Mac replays and
    /// then streams, and replayed events look exactly like live ones.
    private func consume(_ stream: AsyncStream<Wire.Event>) async {
        for await event in stream {
            // `ready` belongs to the connection, not the turn: it is not in
            // the Mac's replay buffer, so it must not advance the cursor.
            if event.kind != "ready" { cursor += 1 }
            switch event.kind {
            case "status":
                if let id = event.session { session = id }
            case "part":
                if let part = event.part { upsert(part) }
            case "permission":
                permission = event.permission
            case "question":
                question = event.question
            case "diff":
                diffs = event.diffs ?? []
            case "idle", "done":
                if event.kind == "done" { running = false; turnID = nil }
            case "failed":
                error = event.text
                if event.transient != true { running = false; turnID = nil }
            case "interrupted":
                // Socket lost mid-answer. If we're on screen, reconnect now;
                // otherwise scenePhase does it when we return.
                if scenePhase == .active { resume() }
                return
            case "unknown":
                // The Mac never got the question, or it aged out. Honest
                // reset: the user re-sends, nothing pretends otherwise.
                error = "That answer is gone — ask again."
                running = false
                turnID = nil
            default:
                break
            }
        }
    }

    private func upsert(_ part: TurnPart) {
        if let id = part.id, let index = rows.lastIndex(where: { $0.id == id }) {
            rows[index] = part
        } else {
            rows.append(part)
        }
    }

    // MARK: - Approvals

    private func answer(_ request: PermissionRequest, reply: String) {
        Task {
            // Face ID stands in front of granting, never of declining.
            if reply != "reject", await !Approver.confirm() { return }
            permission = nil
            var wire = Wire.Request(kind: "permission")
            wire.permissionID = request.id
            wire.project = project
            wire.reply = reply
            for await event in MacLink().run(wire) where event.kind == "failed" {
                error = event.text
            }
        }
    }

    // MARK: - Continuing an existing session

    private func loadTranscript() async {
        guard let session else { return }
        var request = Wire.Request(kind: "transcript")
        request.session = session
        request.project = project
        for await event in MacLink().run(request) {
            switch event.kind {
            case "part": if let part = event.part { upsert(part) }
            case "diff": diffs = event.diffs ?? []
            case "failed": error = event.text
            default: break
            }
        }
    }
}

private struct PermissionSheet: View {
    let request: PermissionRequest
    let reply: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Label(request.permission ?? "Permission", systemImage: "hand.raised")
                .font(.headline)
            if let patterns = request.patterns, !patterns.isEmpty {
                Text(patterns.joined(separator: "\n"))
                    .font(.body.monospaced())
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            if let always = request.always, !always.isEmpty {
                Text("“Always” will allow: \(always.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Reject", role: .destructive) { reply("reject") }
                    .frame(maxWidth: .infinity)
                Button("Always") { reply("always") }
                    .frame(maxWidth: .infinity)
                Button("Allow Once") { reply("once") }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}
