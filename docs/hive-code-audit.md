# Hive code and UX audit

Date: 2026-09-13 · Baseline: `c7c636a` · Scope: the complete bundled plugin and its configuration integration.

This audit supports the [aiswarm technical specification](aiswarm-ux-technical-spec.md). It describes existing behavior, not implemented enhancements. All eight files under `lua/myPlugins/hive.nvim/` (1,750 lines) were read in full, together with `lua/plugins/nvim-hive.lua`, the Hive section of the root README, and relevant keybinding/statusline integration. No plugin-local test suite was found.

The repository's existing graph contains no Hive nodes. Graph vocabulary inspection and existing lessons therefore supplied no useful Hive architecture evidence; the findings below come from source inspection and the isolated checks recorded at the end.

## 1. Architecture and ownership

```text
Neovim commands / mappings
    -> hive.init: config, root, async CLI calls
    -> hive.ui: actions, dashboard, pickers, form
    -> hive.state: snapshot cache, subscriptions, event cursors
          -> bin/hive json                 [periodic reconciliation]
          -> bin/hive events --follow      [ordered journal delivery]
          <- bin/hive-push                 [optional RPC delivery]

Shell orchestrator / hive loop
    -> dispatch: dependencies + priority + WIP limit
    -> tmux agent-<task-id>
          -> hive exec -> provider -> tee logs/<id>.log
          -> finish -> result + task outcome + event + notifications

Both sides share .hive/: task JSON, prompt files, context, results,
transcripts, events.jsonl, sequence counter, mkdir locks, nvim.server.
```

The orchestrator is a role played by a person or an external agent. `hive up` opens an ordinary orchestrator window, a scheduler/status window, and a journal window. It does not launch an orchestration model, consume worker logs into an LLM context, or manage an orchestration conversation. This distinction matters when specifying reporting “into the orchestrator.”

### Complete module map

| File | Responsibilities and noteworthy behavior |
|---|---|
| [init.lua](../lua/myPlugins/hive.nvim/lua/hive/init.lua) | Defaults; memoized absolute root; child environment; argv construction; async `vim.system` wrapper with timeouts and root checks; synchronous wrapper; Snacks/native notifications; validated setup; public forwarding API. `setup()` stops the old session and reconstructs configuration from defaults. |
| [state.lua](../lua/myPlugins/hive.nvim/lua/hive/state.lua) | Singleton session; guarded subscriber delivery; snapshot validation and count recomputation; serialized refresh requests with queued callbacks; task sorting; statusline; ordered event delivery; sequence-gap recovery; follower restart; push registration; teardown and background polling. |
| [ui.lua](../lua/myPlugins/hive.nvim/lua/hive/ui.lua) | All rendering and interactions: tmux navigation, cancel/requeue, scheduler pause, terminal tail, synchronous peek/fallback, task/results pickers, floating dashboard, task form template/parser/submission. State cache and view state are accessed directly. |
| [health.lua](../lua/myPlugins/hive.nvim/lua/hive/health.lua) | CLI doctor JSON, dependencies, `atomic_add`, timeout, board presence, providers, Snacks, current cache/follower status. |
| [plugin/hive.lua](../lua/myPlugins/hive.nvim/plugin/hive.lua) | Loaded guard; ten user commands; prefix completion from cached IDs; visual range capture for `HiveAdd`. Optional ID arguments do not resolve the current selection. |
| [bin/hive](../lua/myPlugins/hive.nvim/bin/hive) | Bash 3.2-compatible control plane, JSON/file storage, locks, task CRUD, dependency scheduler, provider execution, context/report protocol, tmux management, streaming journal, CLI rendering, notifications. Reports version `2.1.0-dev`. |
| [bin/hive-push](../lua/myPlugins/hive.nvim/bin/hive-push) | Reads the registered editor server, canonicalizes the root, escapes Vimscript single-quoted arguments, invokes `require'hive'.on_event_json()` through `nvim --remote-expr`. Failures are deliberately best effort. |
| [doc/hive.txt](../lua/myPlugins/hive.nvim/doc/hive.txt) | Setup, public command/API contracts, form syntax, event guarantees and limitations. References plugin-local README/LICENSE/THIRD_PARTY_NOTICES files that are absent in this checkout. A Hive README section exists at repository root. |
| [nvim-hive.lua](../lua/plugins/nvim-hive.lua) | Local lazy.nvim spec; Snacks dependency; lazy command/key registration; bundled CLI path. Four mappings under `<leader>H`. |

### Backend command families

| Family | Functions/commands and semantics |
|---|---|
| Infrastructure | `with_lock` acquires a `mkdir` lock with approximately 10 seconds of retry; EXIT/INT/TERM cleanup. `task_file/task_state/tget/tset` locate, read and atomically replace task JSON. Atomic file replacement does not make every multi-file operation transactional. |
| Journal | `_next_seq`, `_emit_event`, `event`; counter increment precedes append. `event` extras are strings, can override base envelope keys, and use one subprocess per configured push hook. `progress` is an explicit external hook, not an automatic heartbeat. |
| Initialization/add | `init` creates context templates, task-state directories, logs/results/locks/agents and journal. `add`, under dispatch lock, validates creation flags, allocates an ID if omitted, stages prompt/task files, publishes them, emits `queued`. |
| Scheduling | `ready_sorted` orders a padded priority string and creation timestamp; `deps_ok` requires every dependency's done file. `dispatch` checks pause/WIP, moves each eligible task to active, then calls `spawn`. `loop` dispatches, reaps, clears/renders status and sleeps. |
| Context | `context_pack` includes mission, interfaces, last 40 decision lines and dependency reports; `render_prompt` adds task text and the expected report sections. These are instructions to the provider, not validated enforcement of file ownership or successful verification. |
| Execution | `prepare_dir` optionally creates/reuses `hive/<id>` worktrees; otherwise uses scheduler cwd. `run_provider` supports claude, codex, gemini, aider, cursor and mock. `exec` renders the prompt, records start metadata, emits `started`, runs timeout/provider through tee, then finishes. Stored `mode` is not used. |
| Outcomes | `finish` records exit/duration/cost, synthesizes a report only if absent, moves active to done/failed, emits an outcome, notifies and signals waiters. `reap` treats a missing session as an orphan. `kill` kills the session, resets some fields and moves active to ready. |
| Read surfaces | `json/dump/status --json` return a dispatch-locked snapshot with API v2 and `atomic_add`; `show` adds result/log paths; `tail` reads/follows transcript; `peek` captures tmux pane; `events` scans by sequence and optionally replaces itself with `tail -F`. |
| Editing | `set` updates selected ready-task metadata; `move` subtracts one from another/minimum priority; `edit` opens a ready prompt with `$EDITOR`. These commands do not share creation validation or consistently acquire dispatch locking. |
| Sessions/control | `up/down`, `pause/resume`, `go`, `pick`, `gc`, `wait`, `send`. Pause stops new dispatches; it does not pause running providers. `send` pastes into a pane, although bundled providers execute one-shot commands. |
| Presentation/diagnostics | `status`, `statusline`, `doctor`, `notify`, `context`, `prompt`, `usage`, version. Human doctor treats missing flock as a problem although mkdir provides locking; timeout is checked by Neovim health but omitted from backend doctor. |

## 2. Data flow and guarantees worth preserving

1. **Creation:** the form validates its header, preserves prompt lines, writes a temporary prompt file, and submits argv through `vim.system`. The backend rejects duplicate IDs while holding the dispatch lock. The form remains available after validation/backend errors and suppresses duplicate submission while a request is pending.
2. **Execution:** ready tasks satisfy all dependencies before dispatch; lower priorities run first. Active-file count enforces WIP. Provider output is merged stdout/stderr and saved with `tee`; provider exit status comes from `PIPESTATUS[0]`.
3. **Refresh:** one snapshot request runs at a time. Requests made while it is in flight receive a subsequent snapshot. Validation rejects malformed task identities/states and recomputes counts rather than trusting input counts.
4. **Events:** initial historical events do not trigger notifications. New push/follow duplicates are ignored by sequence, future events buffer until gaps are recovered, and snapshot sequence is tracked separately from delivered-event sequence. These are useful application-level guarantees, conditional on an intact contiguous journal.
5. **Lifecycle:** generation tokens reject stale state callbacks after stop/setup. Jobs and timers are stopped and push registration is removed only if it still belongs to that editor. Subscriber failures are isolated with `pcall`.
6. **Progress:** an accepted progress event sets only an in-memory monotonic timestamp on an already known task. Subscribers and `User HiveEvent` receive the complete event, including `note`; the dashboard retains no note/history.
7. **UI:** dashboard subscribes and unsubscribes on close. Picker items are constructed once from a fresh snapshot. Peek chooses a live pane, transcript, then report. Results directly enumerate report files.

## 3. Findings tied to implementation

“Confirmed” means source behavior or an isolated reproduced behavior. “Risk” means an inferred failure path that has not been reproduced against real processes. P0 identifies correctness/identity issues to resolve before the enhanced control actions ship; P1 identifies core UX/observability work; P2 identifies integration and packaging polish.

| ID / priority | Evidence | Consequence and proposal implication |
|---|---|---|
| A01 / P0 | Confirmed: [gitsigns.lua:22](../lua/plugins/gitsigns.lua#L22), [nvim-hive.lua:20](../lua/plugins/nvim-hive.lua#L20), [which-key.lua:18](../lua/plugins/which-key.lua#L18). | Buffer-local Git mappings shadow Hive picker/results. `<leader>Hr` resets a hunk in tracked code. Move aiswarm to a distinct uppercase `<leader>A` group, with no default legacy key aliases. |
| A02 / P1 | Confirmed: [ui.lua:281](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L281). | Enter closes the board and changes tmux sessions; tail/add/results also close it. Enter on a non-task row can close it without an action. Prefer a persistent inspector and explicit attach. |
| A03 / P1 | Confirmed: [ui.lua:77](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L77). | Peek and picker preview synchronously wait up to 1.5 seconds. File/report fallback reads are also unbounded. Use cancellable async reads with selection tokens and size limits. |
| A04 / P0 | Reproduced: [ui.lua:239](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L239), [state.lua:122](../lua/myPlugins/hive.nvim/lua/hive/state.lua#L122). | Full rerender changes the row-to-ID map without preserving selected ID. A status transition can retarget the next action. Anchor selection/actions to task and attempt IDs. |
| A05 / P1 | Confirmed: [ui.lua:207](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L207). | Fixed-width columns/separator/footer, unbounded titles, byte-oriented padding and hardcoded extmark spans complicate narrow terminals and Unicode. Some spans assume a three-byte glyph even when the glyph has a different encoding. Use display-cell measurement and byte-accurate spans. |
| A06 / P1 | Confirmed: [ui.lua:145](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L145). | Open task pickers do not subscribe to updates; kill can leave stale entries/preview. Reconcile items while preserving query and selected ID. |
| A07 / P1 | Confirmed: [state.lua:144](../lua/myPlugins/hive.nvim/lua/hive/state.lua#L144), [bin/hive:110](../lua/myPlugins/hive.nvim/bin/hive#L110), [bin/hive:344](../lua/myPlugins/hive.nvim/bin/hive#L344). | Output capture and progress events are separate; the runner never derives progress from output or schedules heartbeats. There is no combined live log feed or persisted latest progress projection. |
| A08 / P0 | Confirmed: [bin/hive:606](../lua/myPlugins/hive.nvim/bin/hive#L606), [ui.lua:48](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L48). | “Kill” means immediately requeue, so a running scheduler can launch it again next tick. Define separate cancel and retry operations with explicit outcomes. |
| A09 / P0 | Confirmed/reproduced: [bin/hive:335](../lua/myPlugins/hive.nvim/bin/hive#L335), [bin/hive:352](../lua/myPlugins/hive.nvim/bin/hive#L352). | Reruns overwrite the same transcript/rendered prompt; an existing report is accepted even if the new run writes none. No attempt identity fences a late finish callback. Add immutable attempt paths and generation checks. |
| A10 / P0 | Confirmed: [bin/hive:378](../lua/myPlugins/hive.nvim/bin/hive#L378), [bin/hive:595](../lua/myPlugins/hive.nvim/bin/hive#L595). | `agent-<id>` is global to the tmux server. Different projects collide; `down` kills every `agent-*` session. Namespace sessions by board/attempt and verify ownership before mutation. |
| A11 / P0 | Confirmed predicate / inferred failure: [bin/hive:381](../lua/myPlugins/hive.nvim/bin/hive#L381), [bin/hive:408](../lua/myPlugins/hive.nvim/bin/hive#L408). | `remain-on-exit` retains a session after process death; reaper and `live` only check session existence. A worker wrapper crash can remain active indefinitely. Track process/pane health separately from inspectability. |
| A12 / P1 | Confirmed: [bin/hive:233](../lua/myPlugins/hive.nvim/bin/hive#L233). | Missing/failed dependencies and cycles remain indistinguishable from runnable queued work and can wait forever. Validate dependency graph and expose blocked reasons. |
| A13 / P1 | Confirmed: [state.lua:270](../lua/myPlugins/hive.nvim/lua/hive/state.lua#L270), [ui.lua:424](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L424). | No in-editor initialization/start flow. Missing board, empty queue, paused scheduler and absent scheduler are poorly distinguished. Form/picker require a successful snapshot first. |
| A14 / P1 | Confirmed: [init.lua:30](../lua/myPlugins/hive.nvim/lua/hive/init.lua#L30), [init.lua:91](../lua/myPlugins/hive.nvim/lua/hive/init.lua#L91). | Root freezes at first use; cwd change does not switch projects. `setup()` switching also resets unspecified options. Add an explicit project session API and project indicator. Canonicalize symlinks consistently with push. |
| A15 / P1 | Confirmed: [ui.lua:315](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L315). | Seven technical fields precede the prompt; all errors are toasts; form closes with a wipe buffer; ID allocation is guessed client-side. Introduce prompt-first composition, durable drafts and inline field errors; let backend allocate IDs. |
| A16 / P1 | Confirmed: [ui.lua:320](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L320), [bin/hive:27](../lua/myPlugins/hive.nvim/bin/hive#L27). | GUI defaults to claude, CLI to mock. UI's hardcoded providers differ from doctor's executable names (`cursor` vs `cursor-agent`). Centralize stable provider IDs, discovery and effective defaults. |
| A17 / P1 | Confirmed: [plugin/hive.lua](../lua/myPlugins/hive.nvim/plugin/hive.lua). | Commands accept optional IDs then silently do nothing without one. Resolve contextual selection or open a task picker. |
| A18 / P1 | Confirmed: [ui.lua:295](../lua/myPlugins/hive.nvim/lua/hive/ui.lua#L295), [state.lua:277](../lua/myPlugins/hive.nvim/lua/hive/state.lua#L277). | Every event redraws the whole dashboard; background snapshots run every 3 seconds even when hidden. High-volume log events would amplify work. Separate event ingestion, projections and throttled visible rendering. |
| A19 / P0 | Inferred crash window: [bin/hive:83](../lua/myPlugins/hive.nvim/bin/hive#L83), [state.lua:165](../lua/myPlugins/hive.nvim/lua/hive/state.lua#L165). | Counter is saved before journal append. A crash between them can create a permanent sequence hole and stall ordered delivery. Journal recovery and explicit generation/gap handling are prerequisites for reliable telemetry. |
| A20 / P1 | Confirmed: [state.lua:183](../lua/myPlugins/hive.nvim/lua/hive/state.lua#L183), [state.lua:220](../lua/myPlugins/hive.nvim/lua/hive/state.lua#L220), [bin/hive:519](../lua/myPlugins/hive.nvim/bin/hive#L519). | Recovery scans the full journal and returns all matching lines through a short-command timeout. Pending events and partial-line buffer have no bounds; follower stderr is discarded. Add paging, bounds, backoff, retention-aware cursors and connection diagnostics. |
| A21 / P1 | Confirmed: [state.lua:242](../lua/myPlugins/hive.nvim/lua/hive/state.lua#L242), [bin/hive:97](../lua/myPlugins/hive.nvim/bin/hive#L97). | One registration file targets the latest editor; a registration failure is not retried until setup. Every push forks a process. Followers can support other editors; push should not carry high-volume logs. |
| A22 / P0 | Confirmed: [bin/hive:471](../lua/myPlugins/hive.nvim/bin/hive#L471), [bin/hive:500](../lua/myPlugins/hive.nvim/bin/hive#L500). | Ready-state check and edit are not serialized with dispatch; set applies fields incrementally and omits creation validation. Reproduced invalid provider/negative timeout acceptance. Require revision-checked atomic edits. |
| A23 / P1 | Reproduced: [bin/hive:488](../lua/myPlugins/hive.nvim/bin/hive#L488). | Move-first turns priority 0 into -1, contradicting form/add validation. String sorting pads only up to six digits, so very large priorities can sort unexpectedly. Normalize/rebalance numeric queue ordering. |
| A24 / P1 | Confirmed: [bin/hive:353](../lua/myPlugins/hive.nvim/bin/hive#L353). | Exit 0 alone means done; verification/report completeness is not checked. Cost grep is best effort, and claude requests text. Show execution outcome separately from report quality and verification claims; unknown cost is not zero. |
| A25 / P1 | Confirmed: [bin/hive:297](../lua/myPlugins/hive.nvim/bin/hive#L297). | Requested worktree silently falls back to shared cwd when prerequisites/config are absent. Display and validate effective isolation before queueing. Shared mode requires explicit selection in the proposed composer. |
| A26 / P1 | Confirmed: [bin/hive:158](../lua/myPlugins/hive.nvim/bin/hive#L158), [bin/hive:569](../lua/myPlugins/hive.nvim/bin/hive#L569). | `mode` is stored but unused; headless processes cannot be assumed to accept a message pasted into a pane. Provider capabilities must gate messaging/input actions. |
| A27 / P2 | Confirmed: [bin/hive:115](../lua/myPlugins/hive.nvim/bin/hive#L115), [state.lua:146](../lua/myPlugins/hive.nvim/lua/hive/state.lua#L146). | Multiple notification channels can announce the same completion. `notify.orphaned` has no matching built-in event: reaper emits `failed` with `rc=orphaned`. Centralize type/reason handling and notification policy. |
| A28 / P1 | Confirmed: [bin/hive:48](../lua/myPlugins/hive.nvim/bin/hive#L48), [bin/hive:199](../lua/myPlugins/hive.nvim/bin/hive#L199). | SIGKILL can leave stale lock directories; add publishes prompt then task without a crash recovery transaction. A failed add before init can create a partial board's locks directory. Diagnose and recover owned stale state; do not label staged publication fully crash-atomic. |
| A29 / P1 | Confirmed/inferred: [bin/hive:387](../lua/myPlugins/hive.nvim/bin/hive#L387). | Spawn failure after the active move has no rollback in dispatch. Effective WIP/config values in `json` reflect the invoking CLI environment, not an authoritative scheduler configuration record. Record scheduler identity/config and structured dispatch failures. |
| A30 / P2 | Confirmed: [health.lua](../lua/myPlugins/hive.nvim/lua/hive/health.lua), [bin/hive:630](../lua/myPlugins/hive.nvim/bin/hive#L630), [doc/hive.txt](../lua/myPlugins/hive.nvim/doc/hive.txt). | Version minimums are documented rather than fully verified; provider capability checks are only executable discovery; health messages/documentation references drift. Add versioned capability probes and package docs/licenses before release. |
| A31 / P1 | Confirmed: [bin/hive:101](../lua/myPlugins/hive.nvim/bin/hive#L101). | Arbitrary event extras merge over reserved keys. Most string/path arguments outside add/kill receive weaker validation. Use a validated versioned envelope and allowlisted payload; validate task IDs before using them in paths/session targets. |
| A32 / P2 | Confirmed: [.gitignore](../.gitignore), [lualine-nvim.lua](../lua/plugins/lualine-nvim.lua). | Runtime board files are not ignored here; available Hive statusline is not integrated. Include repository-specific ignore and lightweight statusline changes in the migration inventory. |

## 4. Validation performed

These checks used `/tmp/hive-audit-5gvcd3mp` and `/tmp/hive-ui-audit.lua`. The backend fixture used stub executables for tmux and desktop notification tools; the report regression also used a stub named `codex` that only printed one fixture line. No real provider was invoked and no user tmux session was changed. The ready-to-active fixture move simulated dispatch; it did not validate real scheduling or tmux process management.

| Check | Observed result |
|---|---|
| Backend init/add/mock exec/json/events | Mock finished in done; event types were only `queued`, `started`, `done`; no automatic progress/log events; cost was null. |
| Rerun with existing report; stub provider exits 0 without writing a report | Task became done and report remained exactly `STALE PRIOR ATTEMPT`. |
| Add with nonexistent dependency | Accepted dependency `MISSING`. |
| Move first when minimum priority is zero | Stored priority became `-1`. |
| Set invalid provider and negative timeout | Stored `provider=not-a-provider`, `timeout=-1`. |
| Headless Neovim state delivery of sequence 2, then 1, then duplicate 2 | Subscribers received `[1,2]` exactly once each. |
| Progress note persistence | Task gained `last_progress`; no progress note was stored on task. |
| Form prompt containing a blank line and `#: literal prompt` | Both preserved after the header delimiter. |
| Preview with injected 200 ms synchronous backend delay | Caller blocked approximately 201 ms. This measures the controlled dependency, not actual provider latency. |
| Dashboard selection during active → done reorder | Cursor stayed on row 3; selected task changed from T-001 to T-002. |

Host Neovim was `v0.12.0-dev-1781+g3afe0c6740`. The documented minimum 0.10.4, actual terminal appearance, real provider streaming, crash races, worktree behavior and tmux liveness have not been runtime-validated in this audit. Findings marked as risks need the acceptance fixtures in the technical specification.
