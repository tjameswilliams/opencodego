import Foundation
import OSLog

/// Where a turn's events go: the current connection, held weakly, so a dead
/// socket silently stops receiving and the turn keeps running.
@MainActor
protocol TurnSink: AnyObject {
    func deliver(_ event: Wire.Event)
}

/// Running turns, owned by nobody's socket — the Tomte pattern that makes
/// mobile agents workable at all. iOS suspends the phone's sockets the
/// moment the app leaves the screen; the OpenCode turn on this Mac is
/// unaffected, and when the phone reconnects it asks to `resume` the turn
/// by the id it minted, replaying from wherever it left off.
///
/// Every event of every turn is buffered for its lifetime (turns are small:
/// part snapshots, a permission, a diff), so a resume from 0 rebuilds the
/// whole answer and a resume from N gets only what's new.
@MainActor
final class LiveTurns {
    static let shared = LiveTurns()

    private final class Run {
        var events: [Wire.Event] = []
        var done = false
        weak var sink: TurnSink?
        /// How many events the current sink has been sent.
        var cursor = 0
        var task: Task<Void, Never>?
        var endedAt: Date?
    }

    private var runs: [String: Run] = [:]
    private let logger = Logger(subsystem: "com.timwilliams.opencodego", category: "turns")
    /// Finished turns linger this long for late resumes, then age out.
    private static let retention: TimeInterval = 15 * 60

    /// Starts a turn. `work` runs on the main actor with an `emit` that
    /// buffers each event and pushes it to whichever sink is current. The
    /// worker signals completion by emitting `done` (or `failed` + `done`).
    func start(
        _ id: String, sink: TurnSink,
        work: @escaping (_ emit: @escaping (Wire.Event) -> Void) async -> Void
    ) {
        prune()
        // The same phone retrying the same turn (a reconnect racing its own
        // resume) must not start the work twice.
        if let existing = runs[id] {
            attach(existing, sink: sink, from: 0)
            return
        }
        let run = Run()
        run.sink = sink
        runs[id] = run
        let emit: (Wire.Event) -> Void = { [weak self, weak run] event in
            guard let self, let run else { return }
            self.append(event, to: run)
        }
        run.task = Task { @MainActor in
            await work(emit)
        }
    }

    /// Reconnects a sink to a turn. Replays buffered events from `from`,
    /// then the sink receives the rest live. False when the turn is unknown
    /// — the caller answers `unknown`, and the phone's right move is to ask
    /// again rather than show an error.
    func resume(_ id: String, from: Int, sink: TurnSink) -> Bool {
        guard let run = runs[id] else { return false }
        attach(run, sink: sink, from: from)
        return true
    }

    private func attach(_ run: Run, sink: TurnSink, from: Int) {
        run.sink = sink
        run.cursor = min(max(0, from), run.events.count)
        while run.cursor < run.events.count {
            let event = run.events[run.cursor]
            run.cursor += 1
            sink.deliver(event)
        }
    }

    private func append(_ event: Wire.Event, to run: Run) {
        run.events.append(event)
        if event.kind == "done" {
            run.done = true
            run.endedAt = Date()
        }
        guard let sink = run.sink else { return }
        // Only push contiguously: a sink mid-replay catches up in attach.
        while run.cursor < run.events.count {
            run.cursor += 1
            sink.deliver(run.events[run.cursor - 1])
        }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        runs = runs.filter { _, run in
            guard run.done, let ended = run.endedAt else { return true }
            return ended > cutoff
        }
    }
}
