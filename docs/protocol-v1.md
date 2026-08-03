# Mobile protocol v1 — verified OpenCode mapping

Status: M0 complete. Everything below was exercised live against
**OpenCode 1.18.10** (`opencode serve`, localhost) by `spikes/adapter/spike.ts`
on 2026-08-02. Raw event samples: `spikes/adapter/events/`.

The phone speaks protocol v1 over Wire; the Mac adapter translates to the
installed OpenCode HTTP+SSE API. This file is the contract's ground truth:
every v1 kind lists the OpenCode call(s) behind it and any version skew we
have already observed.

## Conventions

- Instance-scoped endpoints take `?directory=<absolute worktree path>`
  (URL-encoded). The global server multiplexes per-directory instances.
- Async errors do NOT surface on the HTTP call. `prompt_async` returns
  **204 with an empty body** (observed live; the adapter must not JSON-parse
  empty responses) and failures arrive later as `session.error` events /
  server log lines. Never treat prompt_async's success status as "the turn
  is running fine."
- All list/reply calls verified return JSON; SSE is standard
  `data: {json}\n\n` framing with `{id, type, properties}` envelopes.

## v1 kinds → OpenCode calls (all verified)

### `hello` — capabilities
- `GET /global/health` → `{healthy, version}`
- `GET /config/providers` → configured providers + default models
- Capability detection: fetch `GET /doc` (OpenAPI) once and probe
  `components.schemas.Event*` for event-name skew (see below).

### `projects`
- `GET /project` → `[{id, worktree, vcs?, name?, icon?, time{created,updated}, sandboxes}]`
  - Includes a synthetic `id: "global"` entry (worktree `/`) — filter it out.
  - Only projects previously opened with OpenCode; Mac-side git discovery
    supplements this for never-opened repos.

### `sessions`
- `GET /experimental/session?limit=N` → cross-project, recency-sorted
  `[{id, title, directory, ...}]`. Supports `search`, `cursor`, `archived`.

### `prompt`
- `POST /session?directory=…` body `{title?, agent?, model?, permission?: PermissionRule[]}`
  - `permission: [{permission: "bash", pattern: "*", action: "ask"}]` forces
    the approval flow per-session — the phone's "always ask me" toggle.
- `POST /session/{id}/prompt_async?directory=…` body
  `{model: {providerID, modelID}, parts: [{type: "text", text}]}` → 200 immediately.
- Stream: `GET /event?directory=…` (SSE). One subscription per instance;
  `/global/event` exists for all-instance coverage.
- Abort: `POST /session/{id}/abort`.

### `permission`
- Event `permission.asked` → properties are the request itself:
  `{id, sessionID, permission, patterns, metadata: {command}, always, tool: {messageID, callID}}`
  - `always` carries the pattern(s) an "always allow" reply would whitelist —
    show it in the approval sheet.
- Poll fallback (survives missed events): `GET /permission?directory=…` lists
  pending requests. **This is what push-notification handling should read on
  wake** — no event replay needed.
- Reply: `POST /permission/{requestID}/reply` body
  `{reply: "once" | "always" | "reject", message?}`. The blocked tool call
  (state `running`) proceeds immediately on approval.
- Questions are the same shape: `question.asked`, `GET /question`,
  `POST /question/{requestID}/reply` | `/reject`.

### `diff`
Two sources with different lifetimes:
- **Live**: `GET /session/{id}/diff` + `session.diff` events — the pending
  diff while the turn runs; **empties once the session settles**. Use for the
  in-flight "what is it changing right now" view.
- **Durable per-turn**: the *user* message's `info.summary.diffs` from
  `GET /session/{id}/message` →
  `[{file, patch (unified), additions, deletions, status}]`. This is the
  review screen's source.
- `GET /vcs/diff` requires a `mode` query param (working-tree level; not
  needed for v1).

### `resume` / transcript
- `GET /session/{id}/message?directory=…` → full transcript:
  `[{info: {id, role, time, summary?, agent, model}, parts: [...]}]`
  - Part types observed: `text`, `reasoning`, `tool` (with
    `state.status: pending|running|completed` + `state.input/output`),
    `step-start`, `step-finish`, `patch`.
- Reconnect strategy (LiveTurns on the Mac): replay transcript, then live
  events. Message/part IDs are stable — dedupe on them.

## Event catalog (observed on 1.18.10)

Coarse (message-level snapshots, fine for v1):
`server.connected`, `server.heartbeat`, `session.created`, `session.updated`,
`session.status`, `session.idle`, `session.diff`, `session.error`,
`message.updated`, `message.part.updated`, `message.part.delta`,
`permission.asked`, `permission.replied`, `question.asked`,
`file.edited`, `file.watcher.updated`, `todo.updated`, `project.updated`.

Fine-grained delta family (token-level streaming — the right thing to
forward over Wire for typing-effect UX): `session.next.text.delta`,
`session.next.reasoning.delta`, `session.next.tool.input.delta`,
`session.next.tool.called/progress/success/failed`,
`session.next.step.started/ended/failed`, plus compaction/revert/shell
variants. Full list: probe `/doc` `Event*` schemas.

Turn lifecycle as observed: `session.status` → parts stream →
(`permission.asked` → blocked tool `running` → `permission.replied`) →
`session.idle`.

## Version skew already observed (why the adapter exists)

| Concern | Older (≤1.16-era / fork) | 1.18.10 |
|---|---|---|
| Permission ask event | `permission.updated` | `permission.asked` (+ `permission.v2.asked` variant) |
| Question events | `question.*` | `question.*` + `question.v2.*` variants |
| Storage schema | — | 1.16.2 binary + newer DB → `SQLiteError: no such column: replacement_seq`; every prompt dies as an opaque async `prompt_async failed`. Adapter must health-check with a real prompt path, not just `/global/health` (which reported healthy). |

Adapter rule: subscribe to both old and new event names; detect once via
`/doc` and cache per server version.

## Gotchas for the Mac companion

- Start `opencode serve` with `OPENCODE_SERVER_PASSWORD` set (it warns
  "server is unsecured" otherwise) even though it's localhost-only —
  defense in depth against other local processes.
- Session create + prompt are two calls; a session with no prompt is an
  empty shell that still appears in session lists (clean up on abandon).
- `GET /project` ordering is not recency — sort by `time.updated` client-side.
- The model for a prompt comes from the phone's pick of
  `GET /config/providers`; there is no server-side "default model for this
  project" the adapter can rely on across versions.
