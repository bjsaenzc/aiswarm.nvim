# aiswarm.nvim — UX and agent observability proposal

Status: Proposed · Date: 2026-09-13 · Baseline: `c7c636a`

**Recommendation:** evolve AISwarm into `aiswarm.nvim`, a persistent Neovim workspace for coordinating tasks, inspecting execution attempts and following agent activity. Keep the existing Snacks dependency, tmux execution model and local file-based board. Introduce a responsive task list with an inspector, a unified activity feed, and a replayable telemetry contract shared by the editor and external orchestrators.

This is a specification, not an implementation. The accompanying [complete code audit](aiswarm-baseline-audit.md) records the architecture, 32 source-grounded findings and isolated validation. Proposed APIs/configuration below do not exist yet. Runtime performance numbers are acceptance targets, not measurements of AISwarm.

## 1. Problem, goals and boundaries

Today the user must leave the dashboard to inspect output, infer why queued work is waiting, and remember that “kill” actually requeues. The backend captures transcripts but does not automatically report useful activity; the UI retains only the age of manually emitted progress. There is no attempt history, and a rerun can inherit an old report. Improving the visual layer therefore requires fixing identity, lifecycle and observability contracts underneath it.

The first release must let a user answer four questions from one workspace: **What is running? What is it doing? What needs my attention? What happened?**

| Goal | Acceptance target |
|---|---|
| Package identity | Standalone `aiswarm.nvim`, `aiswarm`, `:AISwarm`, `require("aiswarm")` and `AISWARM_*` only. Schema-v2 data remains explicitly importable; there are no alternate plugin entry points. |
| Orientation | A first-time user can initialize a board, select an installed provider and queue a mock task from Neovim without memorizing shell commands. |
| Inspection | From a selected task, activity/output/report is reachable in at most two actions without losing task selection or board context. |
| Real-time reporting | Under the reference load, p95 ≤500 ms from a flushed local worker activity/log record to its display and to receipt by a subscribed external orchestrator process. Provider-side buffering and model response time are measured separately. |
| Honest state | Queue blockers, scheduler pause/stoppage, process health, missing reports and stale telemetry have distinct labels. Cancellation never schedules an automatic rerun. |
| Responsiveness | Cached workspace opening p95 ≤100 ms; interaction/render work p95 ≤16 ms per scheduled UI batch; no synchronous subprocess calls from cursor/preview/render paths. |
| Reliability | Reconnection resumes supported history without duplicate state transitions/notifications; explicit gaps replace silent loss. Old attempts cannot overwrite a newer attempt's state or report. |

Reference load: 10 simultaneous workers, 1,000 task records, 200 normalized activity records/second in aggregate, and 1 MiB/second aggregate raw output for 10 minutes on a local filesystem. Benchmark both supported minimum Neovim and current stable, recording hardware, memory, dropped/coalesced records and latencies. Start with the existing default WIP of 3; 10 is a stress target, not a new default.

Scope includes backend lifecycle repairs, the rename, workspace/composer, automatic output and heartbeat reporting, explicit worker updates, a machine-readable orchestrator subscription, local replay, migration, health and tests. Rich provider-native events are incremental adapters. Automatic task planning, autonomous retry policies, a new orchestration model, shared remote boards, multiplayer editing and built-in merge automation are deferred.

“Orchestrator” means both the human's Neovim workspace and a subscribing external process. The current shell orchestrator window is not itself an AI runtime. The proposal provides durable delivery to that runtime's adapter; it does not claim that writing a journal injects information into an arbitrary model conversation.

## 2. Neovim design references

Research used upstream documentation and published examples on 2026-09-13. The following transfers are design judgments, not claims that those plugins implement agent orchestration. No new dependency is required solely to copy a visual pattern.

| Reference | Documented pattern | Application to aiswarm |
|---|---|---|
| [Snacks picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md), [published visual example](https://github.com/user-attachments/assets/b454fc3c-6613-4aa4-9296-f57a8b02bf6d) | Async finders/matchers, customizable list/preview layouts and actions. | Use Snacks for quick task/project/provider selection and shared window layout primitives; build preview asynchronously. Keep the long-lived workspace in dedicated buffers. |
| [Trouble](https://github.com/folke/trouble.nvim) | Structured sections, tree indentation, filters/sorters, pinned views, configurable focus and preview. | Group by meaningful state, expose dependency blockers, preserve focus, and allow the inspector/feed to pin a task. |
| [Neotest consumers](https://github.com/nvim-neotest/neotest#consumers) | Summary tree, per-test output, accumulated output panel and contextual run/stop/attach actions. | Separate fleet summary, individual attempt output and combined activity. Execution state and output remain linked by stable identity. |
| [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui#configuration) | Independent elements arranged into side/bottom layouts, with temporary floating inspection and element-specific mappings. | Persistent task list + inspector + activity tray; keyboard focus navigation; optional editor-side layout for monitoring while coding. |
| [Neogit](https://github.com/NeogitOrg/neogit#popups) | Context-sensitive action popups using the object under the cursor. | A discoverable action menu shows legal actions and the exact target; cancellation and retry use different verbs. |

The installed Snacks revision is pinned in `lazy-lock.json` to `882c996cf28183f4d63640de0b4c02ec886d01f2`. Its local `snacks/layout.lua` exposes layout/window composition and update hooks. Implementation must test against that revision and an explicitly selected supported revision; upstream examples are not a promise of API compatibility with every installed version.

## 3. Information architecture and appearance

### Primary workspace

`:AISwarm` opens or focuses one workspace for the selected project. Default: a centered floating workspace using 92% of the available width and 86% of height, bounded by the terminal's usable area. Optional `layout="editor"` docks the task list and activity tray alongside normal editing. Closing the workspace releases views and raw-output subscriptions; it leaves the scheduler and agents running.

Wide-layout wireframe, illustrative content:

```text
╭ aiswarm  my-project                       Scheduler running · 2/3 workers ╮
│ All 8   Running 2   Queued 2   Attention 1   Finished 3        / Search   │
├────────────────────────────────┬──────────────────────────────────────────┤
│ RUNNING · 2                    │ T-014  Add session refresh               │
│ > T-014  Add session refresh    │ codex · Attempt 2 · Running · 01:42     │
│   codex   Running tests   2s   │ Isolated worktree · feature/session      │
│   T-015  Update login copy     │                                          │
│   claude  Editing         1s   │ [Overview] Activity Output Report Files  │
│                                │ Current activity                         │
│ ATTENTION · 1                  │ Running focused authentication tests     │
│ ! T-012  Refresh integration   │                                          │
│   Failed · exit 1              │ Dependencies  T-009 ✓                    │
│                                │ Report        Not available yet          │
│ QUEUED · 2                     │ Verification  Running                    │
│   T-016  Wire refresh UI       │                                          │
│   Blocked by T-012             │ Enter inspect   t output   ? actions     │
├────────────────────────────────┴──────────────────────────────────────────┤
│ Activity · All agents                  Live · f pause view · 0 unread     │
│ 14:32:05  T-015  claude  progress  Updated login helper text              │
│ 14:32:06  T-014  codex   tool      Running authentication tests           │
│ 14:32:07  T-012  mock    failed    Test fixture exited with code 1        │
╰ n new task   / filter   Tab next pane   P pause dispatch   ? help  q close╯
```

The heading contains project, actual scheduler status and worker capacity. Protocol sequence numbers, socket paths and raw root paths move to diagnostics. Long project paths remain available through the project action and hover/help detail. “2/3 workers” comes from the scheduler's persisted effective settings, not the editor's environment.

Task rows prioritize title, provider, explicit state, meaningful latest activity and its age. A compact second line is optional; identifiers remain visible for collaboration. Running/attention/queued/finished sections collapse independently. Completed tasks sort newest first; running tasks keep a stable order; queued tasks follow actual dispatch priority. An attention filter includes failed tasks, orphaned attempts and supported input requests. Dependency-blocked tasks remain in Queued with explicit blocker text.

### Responsive behavior

Breakpoints use the **workspace's interior display width**, not total screen columns:

| Available space | Layout |
|---|---|
| ≥110 columns and ≥28 rows | Task list 35%, inspector 65%, bottom activity tray ~25% of height. |
| 80–109 columns and ≥24 rows | Task list plus inspector; activity shares inspector tabs. Remove optional cost and secondary metadata columns. |
| <80 columns or <24 rows | One pane at a time: Tasks / Inspect / Activity. Enter navigates in; Backspace returns with task selection intact. |
| <40 columns or <12 rows | Minimal task picker and command entry; explain that the full workspace needs more space. No invalid window dimensions. |

Resizing recomputes dimensions and wraps/truncates with `strdisplaywidth`, never byte-count padding. Selection, filters, tab and log scroll position survive layout changes.

### Visual system and accessibility

- Theme-linked groups: `AISwarmTitle→Title`, `AISwarmMuted→Comment`, `AISwarmSelected→Visual`, `AISwarmRunning→DiagnosticInfo`, `AISwarmQueued→Comment`, `AISwarmBlocked→DiagnosticWarn`, `AISwarmFailed→DiagnosticError`, `AISwarmDone→DiagnosticOk`, `AISwarmBorder→FloatBorder`. Reapply defaults on ColorScheme without overriding user definitions.
- One accent for focus, semantic colors for status, normal theme surfaces, restrained separators and consistent one-cell padding. Avoid an oversized logo or decoration consuming task space.
- Every state has text; color and icons are supplementary. Support `icons="ascii"`, Unicode and custom icon maps. No mandatory Nerd Font. Test CJK, combining marks and emoji in titles and activity.
- Render only sanitized text in activity/overview. Preserve raw terminal data separately; do not execute control/OSC sequences from transcripts in ordinary buffers.
- A spinner represents known running work, not measured progress. Never invent percent complete, “thinking” state or cost. Disable animation with `motion=false` and stop animation timers while hidden.
- Footer hints follow focused pane/context; `?` opens the full searchable action menu. Errors appear beside the failed operation with a recovery action, plus at most one deduplicated toast.

### Task inspector

Overview shows task prompt summary, current attempt/provider, requested/effective working directory, dependencies and their outcomes, execution timestamps, timeout, last heartbeat/output/activity, report quality and available actions. Tabs:

| Tab | Content and behavior |
|---|---|
| Activity | Selected attempt's typed updates and lifecycle. Toggle task/all-attempt scope; pin scope while moving the task cursor. |
| Output | Bounded, streaming stdout/stderr with search, wrap toggle, follow toggle and an explicit “open full transcript” action. Distinguish streams. |
| Report | Current attempt's Markdown report, with missing/incomplete/synthesized labels. Never silently fall back to a different attempt. |
| Files | Paths from structured artifact events/report parsing with provenance; open file or optional diff viewer. Shared-working-directory diffs cannot be attributed to a single task without stronger evidence. |
| Attempts | Start/end/outcome per execution, including cancellation, failure reason and links to its own logs/report. |

Native provider tool events and explicit worker reports are marked by source. Model-written verification claims are not treated as independently proven test results. Provider exit 0, report presence and verification outcome are three separate facts.

## 4. Interactions and user journeys

### Keybindings and commands

Use `<leader>A` for this configuration; no existing uppercase `<leader>A` mappings were found in the inspected Lua configuration. Lowercase `<leader>a` remains occupied by Sidekick. Register “AI swarm” with which-key and check runtime maps for local/plugin conflicts before installing bindings. Do not install legacy `<leader>Hp/Hr` aliases.

| Entry | Action |
|---|---|
| `<leader>Aa` / `:AISwarm` | Open/focus workspace. |
| `<leader>Ap` / `:AISwarm pick` | Search tasks; Enter opens the task inspector. |
| `<leader>An` / `:[range]AISwarm new` | Compose task; selection becomes prompt context. |
| `<leader>Al` / `:AISwarm activity` | Combined activity view. |
| `<leader>Ar` / `:AISwarm results` | Reports picker with attempt labels. |
| `:AISwarm project` / `:AISwarm health` | Switch/open project; show actionable health diagnostics. |
| `:AISwarm inspect\|output\|report\|attach\|cancel\|retry [id]` | Act on contextual selection, or open a task picker if no target can be resolved. |
| `:AISwarm scheduler start\|stop\|pause\|resume` | Explicit scheduler control. Stop ceases dispatch/reaping; UI warns that existing workers continue and marks monitoring unavailable. Pause only stops new dispatch. |

Workspace-local keys: `j/k` navigate; `Enter` inspect; `Tab/Shift-Tab` cycle panes; `t` output; `R` report; `g` explicit tmux attach; `n` compose; `e` edit a queued task; `x` cancel; `r` retry an eligible terminal task; `P` toggle dispatch pause; `/` search; `?` action menu; `q` close workspace. `f` pauses/resumes **view following** only in activity/output; footer says “pause view,” never just “pause.” `Ctrl-r` requests reconciliation. Avoid changing Neovim's normal `<C-w>` window navigation.

Actions bind to `{board_id, task_id, attempt_id, expected_revision}` when invoked, then validate that target at execution time. If state changed, show “Task changed; review current state” and refresh. Cancellation confirmation names the task/attempt and uses an inline Yes/No prompt; a completed task does not offer cancel. Legacy `AISwarmKill` retains its old cancel-and-requeue meaning during compatibility, with an explicit warning; it must not silently become permanent cancellation.

### First use and recovery

1. Resolve project root from explicit configuration/environment, then nearest existing board in project ancestors, then Git root/cwd as a candidate. Opening the plugin never creates a board by itself.
2. If none exists, show “Create aiswarm board in <project>,” “Open existing board” and health. The chosen create action runs initialization and shows the effective location.
3. Display detected providers and a mock example. Use the same backend-defined default in CLI/composer; choose mock when nothing has been configured. Enqueueing shows whether the scheduler is running; expose “Start scheduler” when needed.
4. Empty, loading, missing board, invalid board, disconnected stream and stopped scheduler receive different views/messages. Offline cached data remains visible with its age. A reconnect action does not destroy drafts or selection.
5. `:cd` does not silently retarget running actions. When the editing project changes, offer a visible project-switch action. Explicit switching increments a session generation, cancels old reads and restores project-scoped view/draft state.

### Task composition and editing

Use a large normal Neovim prompt buffer with a small metadata header: **Title**, **Provider**, **Working directory/isolation**. An expandable Advanced area contains dependencies, priority and timeout. ID is allocated under the backend lock unless the user explicitly enters one. Provider choices show installed/unavailable and supported capabilities; mock is labelled as simulated execution.

Dependencies use a multi-select picker with titles/states. Backend validation rejects missing dependencies, self-reference and cycles, including edits. If a dependency subsequently fails/cancels, the task shows exactly what blocks it and offers edit dependency or retry upstream; it does not silently bypass dependencies. A requested isolated worktree must be created successfully or queueing fails with a recovery action. Shared-directory execution remains an explicit option with its effective path shown.

`Ctrl-s` and `:w` queue the draft. Validation errors appear inline, preserve input and focus the first affected field. Persist project-scoped drafts on edits through a debounced local write; Esc closes to a saved draft and reopening restores it. “Discard draft” is explicit. Preserve the original source path/range as optional context metadata. The old `#:` form remains an advanced import/export mode during migration, with the same validator.

Queued edits use `expected_revision` and one validated atomic update, including the prompt. Queue reorder operates on numeric priorities and rebalances when necessary instead of creating negative priorities. Show the actual dispatch order in the queue.

### Activity and notification behavior

The default feed merges all workers' meaningful milestones, warnings/errors and lifecycle changes. Filter by task, provider, attempt, event kind, severity and search text. Heartbeats update health indicators but stay hidden unless requested; raw stdout is available through Output or an explicit verbose feed filter. No toast per log line.

Following starts at the end. Scrolling up, searching or selecting text suspends autoscroll and increments an unread counter; new events do not move the cursor. `f` resumes; `G` jumps to the end. Changing selected task updates an unpinned inspector but never changes a pinned feed. Group repeated noisy updates with counts while retaining queryable records under the documented retention policy.

Toast only actionable failure, supported input-required and completion according to configuration; aggregate bursts. One notification owner is selected for a given local user session to avoid simultaneous editor/desktop/tmux duplicates. A persistent attention badge remains until viewed. No historical toast replay when attaching to an existing board.

## 5. Domain model and lifecycle

Separate four things currently conflated by AISwarm: task intent, an execution attempt, the scheduler, and the editor connection.

| Entity | Required fields |
|---|---|
| Board | `board_id` (persisted UUID), `schema_version`, `journal_generation`, canonical root, effective scheduler config, creation time. A copied board must be explicitly cloned to gain a new identity before concurrent use. |
| Task | Stable `id`, title, prompt reference, provider ID, dependencies, numeric priority, timeout, requested isolation, revision, current attempt ID, lifecycle state. |
| Attempt | Globally unique `attempt_id`, task/board IDs, ordinal, provider/version/capabilities, immutable execution config, actual cwd/worktree, tmux session/pane, process identity, timestamps, exit/reason, own report/log/telemetry paths. |
| Activity projection | Latest explicit phase/message and provenance; last heartbeat, output and activity timestamps; telemetry status/capabilities. Restored on attachment from persisted records. |
| Scheduler | Board-scoped instance ID, PID/start identity, heartbeat, paused flag, WIP and effective configuration. A lock prevents multiple dispatch loops for one board. |
| Connection | `connecting`, `live`, `reconnecting`, `offline`, `incompatible`; current generation/cursors, last successful read, error and retry time. Independent of agent health. |

Task lifecycle: `queued → running → succeeded|failed|cancelled`; queued can be cancelled; explicit retry of a terminal task creates a new attempt and returns it to queued. Dispatch reservation and spawn failure must terminate/release the reserved attempt atomically. Display substates derive from evidence:

| Display | Definition |
|---|---|
| Queued | Eligible but awaiting scheduler/capacity. |
| Blocked | Queued and a dependency is unsatisfied; enumerate reasons. |
| Starting | Execution attempt reserved, worker has not acknowledged startup. Startup timeout yields a structured failure. |
| Running | Worker/provider process is known alive. Phase is optional. |
| Waiting for input | An adapter explicitly reports an actionable input request. Generic output silence never implies this. |
| Quiet | Process is alive but no output/activity for configurable 60 seconds. Informational, not failure. |
| Telemetry stale | No heartbeat for three 5-second intervals. Health is unknown until process reconciliation, not automatically failed. |
| Failed: orphaned | Reconciliation establishes the expected worker process/pane died without a terminal event. Retained tmux session alone is insufficient evidence. |
| Succeeded / Failed / Cancelled | Terminal attempt result, with report/verification quality shown separately. |

Only the current attempt may update the task's current outcome. Late records from an older attempt enter its history but cannot mutate a new attempt. Cancel targets the owned process tree, allows a configurable graceful interval, force-stops if needed, then emits one terminal outcome. Retry never occurs as a side effect of cancellation. Failed dependency propagation produces blocked reasons, not synthetic execution failures.

Session names become `aiswarm-<board-short>-<attempt-short>`; full IDs are stored as tmux options and verified. `down`, `gc`, `attach`, `peek`, `wait` and cancellation use stored identities and board ownership. Retained panes are inspectable history, separate from running processes.

## 6. Real-time telemetry and orchestrator delivery

### Collection architecture

Keep Bash as the command/bootstrap interface and preserve tmux ownership. Add small Lua helpers hosted by **clean, headless Neovim** for worker I/O collection and stream multiplexing. They load only the bundled runtime modules, never the user's configuration, plugins or shada. This reuses an existing plugin dependency and avoids a new Python/Node service. It adds an explicit Neovim runtime requirement to the v3 shell worker/stream features; document that tradeoff, resolve the executable absolutely, and measure per-worker overhead before adopting the implementation.

```text
provider stdout/stderr ──> worker helper ──> attempt raw logs
provider native events ─> adapter        ─> attempt telemetry journal
explicit worker update ─> worker inbox   ─> same telemetry writer
worker watchdog ────────────────────────> heartbeat/process observations
                                                   │
Bash control commands ─> validated lifecycle writer │
                         board control journal     │
                                   │               │
                                   └───────┬───────┘
                                    aiswarm stream
                                  replay + multiplex
                                     /           \
                        Neovim transport       orchestrator adapter
                        projections/views     persistent bookmark + ack
```

Use a single telemetry writer per attempt. Explicit `aiswarm progress`/`report-event` commands place validated messages in an atomic spool/inbox for that writer rather than concurrently appending its file. Worker/stream helpers use asynchronous process and file APIs with bounded queues. A headless worker owns provider stdout/stderr, exit status and watchdog; its death is detected by scheduler reconciliation. Selected pane capture is an optional inspection fallback, not the source of structured status.

Avoid spawning `jq`, `aiswarm-push`, or `nvim --remote-expr` for each output line. The existing journal follower demonstrates useful cursor handling but `tail -F` plus periodic snapshots does not itself meet the latency target. The stream helper watches file changes with a bounded 250 ms polling fallback; it incrementally reads offsets and drains records without restarting a process on each event.

### Two channels with explicit ordering

1. **Control journal:** low-volume durable task/scheduler/attempt lifecycle changes, globally ordered by `(board_id, journal_generation, control_seq)`. Validated state changes and their journal events share one serialization boundary. Treat committed events as a write-ahead record and task files as rebuildable projections: append/flush the event before applying the atomic projection update; recover projections before serving a snapshot. A counter file is a cache, never authority over a missing append. Allocate the next sequence from the last valid committed record after recovery. Partial trailing records are quarantined/recovered explicitly.
2. **Attempt telemetry:** higher-volume progress, tools, log references and heartbeats, ordered by `(attempt_id, stream_generation, attempt_seq)`. One writer means no global event lock per output line. Append the telemetry record, then atomically update the latest-activity projection; rebuild that projection if a crash interrupts it. Raw output uses byte-offset cursors and separate stdout/stderr files.

The combined feed uses observed timestamps with source ID/sequence as a deterministic tie-breaker. It does **not** claim a total causal order across independent workers. Lifecycle transitions depend on control order; a telemetry event arriving before its attempt is known buffers briefly and triggers reconciliation. Attempt identity prevents misattribution during retries.

All task/attempt state mutations, including add/edit/reorder/cancel/finish, pass through the same v3 validation/transaction code. Merely adding telemetry beside the current nontransactional setters is insufficient. Snapshots return the last fully applied control sequence. Recovery keeps the existing distinction between snapshot revision and already-delivered events.

### Versioned envelope

Example telemetry record; fields in this example are the proposed schema:

```json
{
  "schema_version": 1,
  "board_id": "57fc3ea0-6b8f-45c2-8e8f-3a5f98cc4ed3",
  "task_id": "T-014",
  "attempt_id": "6520181b-1cb0-4563-985b-3b60d78775db",
  "source": "worker",
  "stream_generation": "1",
  "attempt_seq": 37,
  "event_id": "6520181b-1cb0-4563-985b-3b60d78775db:1:37",
  "observed_at": "2026-09-13T19:32:06.214Z",
  "type": "agent.progress",
  "level": "info",
  "payload": {
    "phase": "testing",
    "message": "Running focused authentication tests",
    "provenance": "worker_report"
  }
}
```

Control records substitute `journal_generation` and `control_seq` for the attempt sequence and may omit task/attempt IDs for board events. Reserved fields cannot be overridden by payload keys. Every emitter validates lengths/types/IDs and numeric fields; unknown additive fields are ignored by older readers. Unknown event types remain inspectable without changing task state. Unsupported schema major versions produce a visible incompatibility state.

| Record | Source and projection |
|---|---|
| `task.queued`, `task.edited`, `task.blocked`, `attempt.started`, `attempt.finished`, `task.cancelled`, `scheduler.changed` | Backend facts; typed lifecycle payload with revision/reason. Only authoritative control records mutate lifecycle. |
| `agent.heartbeat` | Worker watchdog every 5 seconds; process identity/aliveness, not a claim of productive progress. |
| `agent.progress` | Explicit worker update or adapter-native milestone; optional phase and finite total/completed units only when reported. |
| `agent.tool.started/finished` | Adapter-provided public tool metadata and result, with tool/call correlation IDs. |
| `agent.input_required` | Only a provider adapter supporting a real response channel; includes request ID and supported response actions. |
| `agent.output` | Batched references to flushed raw log byte ranges; small sanitized preview plus stream name. Update last-output time. |
| `agent.artifact`, `agent.usage` | Report/file artifact reference; supported usage values and provenance. Missing or unavailable usage stays null. |
| `telemetry.warning`, `stream.gap`, `stream.status` | Parser/collection issues, explicit retention/truncation gap, connection state. They do not claim task failure. |

Capture only provider-exposed output and operational metadata. Do not attempt to infer or expose hidden reasoning. The default feed can say “Output received” when only raw output exists; it cannot infer “Editing” or “Testing” from elapsed time. Worker-authored updates are labelled as reports, not independently observed facts.

### Provider capability contract

Each adapter implements `probe()`, `build_argv(attempt)`, incremental `parse_stdout/parse_stderr()`, and `finish(exit)`; interactive response/cancellation hooks are optional explicit capabilities. Execution options remain argument arrays. Central registry owns stable IDs (`cursor` maps to `cursor-agent`), executable/version checks, defaults and availability.

| Capability | Initial expectation |
|---|---|
| Raw output, process start/exit, heartbeat | Required for every existing provider and mock through the worker wrapper. |
| Explicit progress/report-event | Available to workers through an absolute helper path and board/task/attempt environment, described in their rendered protocol. Does not depend on model cooperation for basic liveness/output capture. |
| Structured tool/activity/usage | Enable per adapter only after checking that installed CLI version's supported output contract and passing recorded fixtures. No speculative flags in the initial migration. |
| Interactive messaging/input | Disabled for current one-shot runners unless a tested adapter supplies a real protocol. Pasting text into a dead/retained pane is not a response channel. |

The bundled mock gains deterministic scenarios: quiet-running, multi-line/partial output, progress milestones, interleaved stdout/stderr, success, failure, timeout, missing report, input-request fixture, output flood and late finish. Adapter parser failure preserves raw output and displays degraded telemetry; it must not turn a successful execution into a false failure.

### Replay, consumers and acknowledgements

Proposed CLI interface:

```sh
aiswarm stream --follow --format jsonl --consumer orchestrator-main
aiswarm stream --follow --cursor '<opaque-cursor>' --types lifecycle,progress,warning
aiswarm ack --consumer orchestrator-main --cursor '<opaque-cursor>'
aiswarm logs T-014 --attempt 2 --follow --stream stdout
aiswarm progress --task T-014 --attempt '<attempt-id>' --phase testing --message 'Running focused tests'
```

`stream` first emits a connection frame with board/generation/capabilities and a snapshot checkpoint, then event frames containing `{event, next_cursor}`. The snapshot includes tasks, attempts, effective scheduler settings, latest activity projections and their individual checkpoints. Snapshot/checkpoint acquisition plus subsequent replay must cover events appended during connection. Per-source telemetry projections carry their own sequence; attach reads after those checkpoints rather than assuming the control sequence covers output.

The opaque cursor encodes board identity, control generation/sequence, telemetry source generations/sequences and raw-log positions when requested. The transport advances it only for fully emitted records; pagination ends with a resumable cursor. UI bootstrap can request the most recent 200 feed entries for context but suppresses historical notifications.

Delivery is **at least once** after reconnect. Consumers deduplicate by event ID. `ack` atomically persists a consumer bookmark only after that consumer accepts/processes a batch; no connection implicitly acknowledges another consumer's events. Consumers are independently named, validated and board-scoped. A disconnected orchestrator resumes from its bookmark. Retention expiration or journal replacement returns an explicit `stream.gap`/`resync_required` and a new snapshot, never an apparently contiguous successful replay.

An external agent adapter reads and groups new records into a bounded update such as: “T-014 testing; T-012 failed exit 1; T-016 blocked by T-012,” preserving links to event/attempt IDs. It forwards that update through the external orchestrator's **documented input API** and then acknowledges. Acknowledge only a durable inbox handoff if that runtime processes asynchronously; state that boundary in its adapter. If no input API exists, offer the live subscription, a generated local briefing and explicit copy/export; do not pretend arbitrary terminal injection delivers a model message. The first acceptance fixture uses a real subprocess consumer and persisted acknowledgement, independent of any paid provider.

### Backpressure, retention and failure handling

- Flush visible output batches at most every 100 ms or 16 KiB, whichever occurs first. Parse incomplete UTF-8 and split JSON lines across callbacks; cap a single normalized event at 64 KiB and refer to the full raw artifact for oversized content.
- Suggested initial bounds: 2,000 activity records/4 MiB globally in the editor; 500 records per selected attempt; 10,000 visible output lines/2 MiB per open output view. Unselected transcripts stay on disk and load on demand. Partial-frame buffer limit: 256 KiB; malformed/oversized records generate one rate-limited diagnostic with a raw reference.
- Per-attempt raw logs rotate at a combined 100 MiB cap; telemetry at 50 MiB. Keep inactive attempt history 7 days by default, configurable. Preserve reports/control outcomes until explicit archive. Track segment identity/offsets so readers see an explicit gap after eviction. Never delete files still being written; retention rotates/evicts only closed segments.
- The UI coalesces repetitive heartbeats/output previews first. Raw bytes are stored independently of display rate. Bounded worker write queues drain even when the editor is closed. On storage exhaustion, mark transcript capture degraded, drain provider pipes without blocking execution indefinitely, count discarded bytes and persist a gap when storage recovers. If a lifecycle commit cannot be persisted, show an explicit recovery-required condition rather than claiming durable success.
- Reconnect with exponential backoff from 250 ms to 5 seconds plus jitter. Display last successful reception and retry action. Reset backoff after a healthy interval. Persisted projections repopulate activity after restart.
- Reconcile snapshots on lifecycle gaps/reconnect and on a slower configurable 10-second fallback; scheduler/process health uses its own interval. Do not start a snapshot request per raw output record. Closing/switching views cancels reads, watchers and subscriptions and rejects late callbacks by generation and selection token.
- Default high-volume delivery uses `stream`, not the legacy push hook. Legacy push remains a low-volume compatibility path; deduplication must tolerate both paths for the same control event.

## 7. Implementation structure and API

Refactor the 429-line UI and 283-line state singleton into components with explicit ownership. This split follows responsibility, not a requirement to create one abstraction per function.

```text
aiswarm.nvim/
  bin/aiswarm, bin/aiswarm-push           canonical launchers
  runtime/worker.lua, runtime/cli.lua  clean headless entry points
  lua/aiswarm/
    init.lua, config.lua, commands.lua, health.lua
    project.lua                         board selection/session lifetime
    backend.lua                         typed command client, timeouts
    protocol.lua                        shared schemas/validation
    transport.lua                       framing, cursors, replay, reconnect
    store.lua                           lifecycle reducer and projections
    runtime/                            worker I/O, journal, stream helpers
    providers/                          registry and tested adapters
    ui/workspace.lua, ui/tasks.lua, ui/inspector.lua
    ui/activity.lua, ui/loader.lua, ui/composer.lua
    ui/actions.lua, ui/highlights.lua
  plugin/aiswarm.lua
  doc/aiswarm.txt
  tests/                                fixtures and headless/backend checks
```

The shared protocol validates both UI and backend inputs, but the backend always validates independently. Runtime entry points discover only bundled module paths. Transport owns jobs/timers; store owns data/cursors; workspace owns windows/subscriptions and selection; views never call subprocesses during rendering. Action handlers receive stable identity plus revision. Cached selections are not authority to mutate current state.

Proposed public surface:

```lua
require("aiswarm").setup({
  bin = "/absolute/path/to/aiswarm.nvim/bin/aiswarm",
  root = nil,
  ui = { layout = "float", width = 0.92, height = 0.86, icons = "unicode", motion = false },
  telemetry = { enabled = true, heartbeat_ms = 5000, flush_ms = 100, reconcile_ms = 10000 },
  notify = { failed = true, completed = true, input_required = true, progress = false },
})

require("aiswarm").open({ task = "T-014", tab = "activity" })
require("aiswarm").project.open("/path/to/project")
require("aiswarm").statusline() -- cached; no I/O
local unsubscribe = require("aiswarm").subscribe(function(event) end)
```

All proposed settings must have validated types/ranges and documented ownership. Root switching is separate from `setup()` so it preserves preferences. `User AISwarmEvent` is the single normalized control-event hook. A lualine component reads cached counts/attention/connectivity and does not trigger lazy loading or subprocesses every redraw.

## 8. Standalone replacement and data migration

The replacement decision of 2026-09-14 supersedes the transitional namespace strategy in the historical plan. The package has one installable identity; storage migration remains a separate, explicit operation. The [implementation audit](aiswarm-implementation-audit.md) distinguishes current behavior from this target specification.

| Surface | Required contract |
| --- | --- |
| Package | Repository root is the plugin root. lazy name `aiswarm.nvim`, `main="aiswarm"`, one command trigger `AISwarm`; examples live in `examples/lazy.lua`. |
| Lua/API | `require("aiswarm")` owns one session/store. No alternate namespace shims. Internal schema adapters are not a second public plugin. |
| Commands | `:AISwarm` subcommands only; no prefixed command aliases. Existing CLI command spellings may remain under the canonical executable with explicit semantics. |
| Executables/environment | `aiswarm`, `aiswarm-push`, `aiswarm-progress`, and `AISWARM_*`. Root precedence: explicit selection → AISWARM_ROOT → discovered board. |
| Board storage | New boards use `.aiswarm/`; only that directory is auto-discovered. Any existing schema-v2 board can be opened by an explicit path. Never move or merge data automatically. |
| Events | `AISwarmEvent` and canonical RPC callbacks; preserve root checks, event deduplication and owner-checked server registration. |
| Sessions/worktrees | New resources use board/attempt identities. Existing recorded resource names and artifact paths are data, not names to rewrite blindly. |
| Integration | README, help, example lazy/which-key/lualine configuration and scripts name this package only. Ignore `.aiswarm/`. Do not claim dependency versions are locked when no lockfile exists. |
| Licensing | Retain the bundled Bash public-domain/CC0 header and the actual MIT notice; do not invent upstream attribution or license conversion. |

### Upgrade procedure

1. `aiswarm migrate --dry-run` inventories schema, active workers, scheduler, locks, absolute paths, reports and potential identity conflicts. It writes no board data.
2. `aiswarm migrate` requires old scheduler/workers to be stopped and no live legacy writer/push hook. Acquire a board migration lock; make a timestamped backup and record a manifest/checksums. Compatibility wrapper clients honor the migration marker; unknown old binaries are unsupported during the maintenance window.
3. Generate board identity and import existing tasks/outcomes into v3. Create one `legacy` attempt for existing execution evidence, explicitly marked as imported with unknown history. Do not invent prior retries or progress. Keep raw logs/reports intact. Translate ready/active/done/failed to the new lifecycle only when their actual state is reconciled.
4. Write upgraded state to a staging area, validate referential integrity and journal projections, then atomically publish the schema manifest as the final commit marker. Interrupted migration can resume/roll back from its manifest. Do not run old and new schemas as dual writers.
5. On first open, show the migrated board, imported-history labels and next actions. Restart the scheduler only through the explicit start action; migration itself does not execute tasks.

Schema v2 mode supports existing monitoring and established v2 actions, with a visible “Legacy board: upgrade for attempt history and structured telemetry” message. It cannot offer reliable per-attempt history, v3 cancellation or full telemetry guarantees. Compatibility commands on a v3 board translate to validated v3 operations; bundled old `aiswarm kill` deliberately translates to cancel followed by explicit requeue in a serialized operation.

Rollback before v3 work starts restores the backup and old launcher configuration. Once v3 has new attempts/events, downgrading by overwriting the board would lose data; export those artifacts and explicitly resolve them before restoring. Retain migration backups until the user archives them. A later optional directory move must rewrite/verify paths and registrations while no worker is active.

## 9. Delivery plan and acceptance tests

Deliver in reviewable increments; UI polish depends on reliable lifecycle/identity rather than concealing inconsistent backend state.

| Phase | Deliverable | Exit gate |
|---|---|---|
| 0 — Baseline fixtures | Record current CLI/state contracts and mock scenarios; establish lowest supported Neovim/Snacks combinations. | Reproduce the audit regressions and keep current ordering/form-preservation behavior covered. |
| 1 — Brand and compatibility | Canonical aiswarm entry points, noncolliding keys, corrected help/health, explicit project selection. | Existing v2 mock board opens through the canonical package using one runtime/store; no runtime data moved; Git/Sidekick keys remain distinct. |
| 2 — Lifecycle foundation | v3 board/attempt IDs, transaction/recovery, revision checks, cancellation/retry, dependency reasons, ownership checks and migration. | Crash/concurrency and two-project fixtures pass; no stale report/late outcome crosses attempts. |
| 3 — Workspace and composer | Responsive persistent views, asynchronous previews, stable selection, drafts, inline validation, accessibility. | Wide/medium/narrow keyboard journeys pass; no blocking preview; selection remains on the same task through reorder. |
| 4 — Telemetry and orchestrator | Worker wrapper, generic logs/heartbeat/progress, stream/replay/ack, combined activity and output, process health. | Latency/load/reconnect/consumer-ack gates pass with mock and stub processes; explicit gaps and bounded memory demonstrated. This completes the core proposal. |
| 5 — Provider richness and release | Tested provider-native adapters, optional usage/tools/artifacts/input, integrations and package documentation. | Each advertised provider capability has a versioned fixture and manual smoke evidence; unsupported capabilities remain disabled. |

Do not advertise aiswarm's real-time orchestrator reporting as delivered after phase 1 or 3. Release the complete baseline after phase 4; phase 5 capabilities can follow independently. Estimate effort after the worker/runtime spike and migration prototype; the proposal intentionally avoids a calendar estimate unsupported by those two uncertainties.

### Required verification matrix

| Area | Cases and required assertions |
|---|---|
| Identity/concurrency | Two boards with T-001 on the same tmux server; cancel/down/gc only affect the selected board. Simultaneous add allocates unique IDs. Edit races dispatch and returns a conflict rather than partial update. Late finish cannot change the current attempt. |
| Lifecycle | Cancellation does not redispatch on the next tick; retry creates a new attempt/log/report. Timeout, provider-not-found, spawn failure, dead pane with retained session and wrapper crash all produce accurate reasons or explicit unknown-health states. |
| Storage/recovery | Crash before/after event append/projection/counter update; stale lock ownership; interrupted migration; truncated journal frame; lost sequence sidecar. Recover contiguous committed records without silently discarding evidence. |
| Dependencies | Missing/self/cyclic dependencies rejected; failed/cancelled upstream produces a visible blocker; retrying upstream can unblock only after success; queue order matches numeric backend priority. |
| Stream/replay | Split lines/UTF-8, duplicate/out-of-order records, event before task projection, reconnect after final completion, generation change, rotation/gap, malformed/oversized record, two independent consumer bookmarks, restart before/after ack. |
| Orchestrator handoff | Spawn a consumer that writes accepted event IDs durably and acknowledges afterward; kill/restart it at both boundaries. All retained events are eventually accepted; duplicates are safely ignored; expired history yields explicit gaps. Test downstream input API separately for any model-runtime integration. |
| Logs/load | Ten mock workers and defined flood load; bound UI/worker queues, inspect only one transcript, close/reopen views, suspend scrolling, simulate disk-full and slow writes. Report latency distribution, memory, CPU, truncation/gap counts and raw bytes captured. |
| UX | Missing vs empty vs stopped board; keyboard-only new→run→inspect→cancel→retry→report; input errors retain drafts; actions target original IDs; blocked reason visible; no-output is different from failed read; restoring project preserves preferences. |
| Layout/theme | 140×45, 100×30, 80×24, 60×20, 35×10; live resize; light/dark themes; ASCII/no Nerd Font; CJK/combining/emoji titles; long paths; thousands of tasks; render does not steal focus or log scroll. Capture actual terminal screenshots for review. |
| Compatibility | Single canonical namespace/command registration, AISWARM environment precedence and push callbacks; explicit v2 board selection; documented kill semantics; one store/follower; migration backup/rollback; help links resolve. |
| Cleanup | Repeated open/close, project switch, setup and exit leave no obsolete timers/watchers/jobs/subscriptions or registration ownership errors. Headless helper uses no user configuration. |
| Platform/providers | macOS Bash 3.2 + GNU timeout and Linux; actual supported Neovim minimum/current stable; pinned Snacks. Real provider smoke tests explicitly record versions and capabilities. Never use paid provider runs as required deterministic unit tests. |

## 10. Decisions, tradeoffs and remaining validation

- **Keep Snacks:** it already provides the needed window/picker/terminal primitives. A new UI framework would add migration work without addressing the observed data/lifecycle problems.
- **Task list plus inspector as the default:** readable titles and in-place detail work in typical terminals. A Kanban presentation can be added later, but would not replace dependency explanations and attention filtering.
- **Separate control and telemetry journals:** lifecycle retains strong ordering; high-volume logs avoid contending on one global Bash lock. The cost is a composite replay cursor and explicitly partial cross-worker ordering, both exposed in the protocol.
- **Reuse headless Neovim for I/O helpers:** no new language runtime for plugin users, but added standalone-CLI requirement and per-worker overhead. Phase 0 must demonstrate acceptable process-tree control, memory and stream latency; if it fails, revisit the runtime before implementing provider adapters.
- **Progress degrades honestly:** generic adapters guarantee captured output/process observations, not provider-internal phase or token-level streaming. Verify each provider's current protocol at implementation time and label unavailable features.
- **Upgrade intentionally:** preserving existing v2 boards while refusing concurrent old/new writers limits migration risk. Users can adopt the new UI/name before upgrading data, with explicit feature limits.

The source audit and temporary fixtures establish the existing problems. They do not validate the proposed architecture's latency, terminal appearance, filesystem durability or real-provider behavior. The phase gates above are the evidence required before claiming those outcomes.
