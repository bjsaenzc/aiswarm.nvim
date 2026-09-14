# aiswarm remediation SDD plan

Status: **active** · Date: 2026-09-14 · Source: [implementation audit](aiswarm-implementation-audit.md) (defects D01–D20 and §5 deviations), [UX technical specification](aiswarm-ux-technical-spec.md), [historical implementation plan](aiswarm-implementation-sdd-plan.md).

This plan continues the numbering of the historical plan (SDD-108 onward) so evidence records keep one namespace. It follows the same execution rules (specification-driven: requirement → contract → implementation → observable verification → recorded evidence), the same runner (`bash scripts/test-aiswarm.sh --task SDD-1xx`), the same evidence ledger and the same validator:

```sh
PLAN=docs/aiswarm-remediation-sdd-plan.md EVIDENCE=<dir with only this plan's records> bash scripts/validate-aiswarm-plan.sh
```

Cards below depend only on cards in this plan; the historical cards they refine are named in **Context**. A card is complete only when its verification passes and a record exists; a card whose fix reveals a further specification conflict produces a decision record, not a silent scope reduction. No card authorizes operating a user's live board or running paid providers.

## 1. Requirement traceability

Requirement labels are those of the historical plan; owners are the remediation cards.

| Requirement | Focus of the remediation | Owning tasks |
|---|---|---|
| R01 Brand/compatibility | legacy actions through the canonical client, CLI spellings, legacy module retirement | SDD-118, SDD-131, SDD-136 |
| R02 Project/first use | project switch on `:cd`, open-board path entry, invalid board and reconnecting states | SDD-122 |
| R03 Persistence | reducer type gating, whole-transaction quarantine, interior corruption diagnostics | SDD-132, SDD-133 |
| R05 Attempts/isolation | guarded worker commits, lock scope, board-scoped worktrees, single-transaction kill and race outcomes | SDD-134, SDD-135, SDD-140, SDD-141 |
| R06 Migration | migration lock and marker honored by every writer | SDD-139 |
| R07 Workspace | no synchronous work in interactive paths, ADR key semantics, ASCII everywhere | SDD-126, SDD-129 |
| R08 Inspector/actions | loader cache, board-scoped targets, row targeting, context preserved on open, output search, overview/report content | SDD-111, SDD-112, SDD-119, SDD-120, SDD-123, SDD-125 |
| R09 Composer | dependency multi-select, `--legacy` without range, draft chooser | SDD-124 |
| R10 Activity/notifications | honest bounds, attempt-aware coalescing, no historical toasts, single owner, reachable pinned scope | SDD-113, SDD-114, SDD-115, SDD-116, SDD-117 |
| R11 Worker telemetry | inbox robustness, normalizer wiring, guarded commits | SDD-138, SDD-144 |
| R12 Replay/consumer | cursor completeness (`--since`, log positions, generation change mid-follow) | SDD-143 |
| R13 Bounds/retention | scheduled retention with explicit gaps, honest editor bounds | SDD-115, SDD-137 |
| R14 Lifecycle cleanup | timers, caches and finder churn released with the views | SDD-128 |
| R15 Provider capabilities | normalizer either wired or removed; no silent adapter hooks | SDD-144 |
| R16 Accessibility | highlight groups at load, ASCII icons in statusline/toasts | SDD-121, SDD-126 |
| R17 Integration/package | documentation consistency, dead configuration switches, normalized `subscribe()`, doctor/health parity | SDD-109, SDD-127, SDD-130, SDD-142 |
| R18 Release evidence | probes as regression tests, retained evidence, re-run acceptance, close core | SDD-108, SDD-145, SDD-146 |

## 2. Delivery order and gates

| Work package | Tasks | Completion boundary |
|---|---|---|
| Regression baseline | SDD-108, SDD-109 | Every audited defect has a failing test; documentation links, help and messages are consistent. |
| Editor correctness | SDD-111–SDD-121 | Probe-confirmed client defects fixed; dispatch resumable; no toast replay; single notification owner. |
| Editor completeness | SDD-122–SDD-131 | Specification §3/§4/§7 contracts met; legacy module retired. |
| Runtime correctness | SDD-132–SDD-144 | Journal, worker, lock, migration, retention, inbox and cursor gaps closed. |
| Release | SDD-145, SDD-146 | Evidence retained in the repository; acceptance matrix re-run; core closed against the specification. |

Within a package only the explicit dependencies constrain order. Editor and runtime packages are independent of each other except where stated.

## 3. Task backlog

### Regression baseline

#### [ ] SDD-108 — Turn the audit probes into failing regression tests

- **Requires:** none. **Requirement:** R18. **Scope:** `tests/audit/`, new cases under `tests/workspace/`, `tests/lifecycle/`, `tests/telemetry/`.
- **Context:** audit D01–D07; `tests/audit/implementation_probe.lua` is diagnostic only and never fails.
- **Deliver:** one tagged `*_test.lua` case per probe observation (loader tail after head, cross-board target, per-attempt bound, attempt-aware coalescing, byte accounting with a retained raw payload, unknown control type, large incomplete transaction). Each case asserts the specified behavior and therefore fails on this tree.
- **Verify:** `--task SDD-108` reports exactly seven failures before any fix and zero after SDD-111–SDD-115, SDD-132 and SDD-133 pass. The probe script is deleted or reduced to a pointer at the tests.

#### [ ] SDD-109 — Repair documentation consistency

- **Requires:** none. **Requirement:** R17. **Scope:** `README.md`, `doc/aiswarm.txt`, `docs/aiswarm-release-checklist.md`, `examples/`, user-facing messages.
- **Context:** audit §5.3; core case `docs.help_tags_and_links_resolve` failed on missing links.
- **Deliver:** help lists every registered `:AISwarm` subcommand including `tail`, `peek`, `kill`, `pause`; README references only examples that exist (add `examples/which-key.lua` or drop the mention); messages never cite nonexistent commands (`:AISwarmKill`, `:AISwarmTail` → `:AISwarm kill`, `:AISwarm tail`); `config.lua:90` comment corrected; the release checklist states the reopened status and links the audit; the specification's and plan's `AISwarmKill` mentions read `aiswarm kill`.
- **Verify:** `docs.help_tags_and_links_resolve` passes; a new case greps `lua/` and `doc/` for `AISwarm[A-Z]` command names and finds none; the checklist no longer claims R18 passed without artifacts.

### Editor correctness

#### [ ] SDD-111 — Key the loader cache by read parameters

- **Requires:** SDD-108. **Requirement:** R08. **Scope:** `lua/aiswarm/ui/loader.lua`.
- **Context:** D01. The key `path:mtime:size` serves a head read to a tail request and a 64 KiB preview to a 2 MiB Output read.
- **Deliver:** cache key includes `tail` and `max_bytes` (or the byte range actually read); identical requests still hit.
- **Verify:** SDD-108 loader case passes; picker preview then Output tab of the same transcript show different, correct byte ranges; cache hit count unchanged for repeated identical reads.

#### [ ] SDD-112 — Scope action targets to the board

- **Requires:** SDD-108. **Requirement:** R08. **Scope:** `lua/aiswarm/ui/actions.lua`, `lua/aiswarm/backend.lua`.
- **Context:** D02; specification §4 binds actions to `{board_id, task_id, attempt_id, expected_revision}`.
- **Deliver:** `target()` captures `board_id` and the project generation; `revalidate()` rejects a target whose board or generation differs with "Task changed; review current state (board changed)"; backend calls made by an action carry the captured root.
- **Verify:** SDD-108 cross-board case passes; capture a target, `:AISwarm project open` another board with the same task id, run cancel → conflict, no backend call.

#### [ ] SDD-113 — Enforce the per-attempt activity bound

- **Requires:** SDD-108. **Requirement:** R10. **Scope:** `lua/aiswarm/store.lua`.
- **Context:** D03.
- **Deliver:** at most 500 records per attempt are retained; the oldest of that attempt is evicted first and a per-attempt gap flag is set; the global bounds are unchanged.
- **Verify:** SDD-108 bound case passes; the Activity tab shows the gap label for that attempt; global eviction order for other attempts is unaffected.

#### [ ] SDD-114 — Coalesce activity by attempt identity

- **Requires:** SDD-108. **Requirement:** R10. **Scope:** `lua/aiswarm/store.lua`.
- **Context:** D04; specification §6 "attempt identity prevents misattribution".
- **Deliver:** repeats merge only when task, attempt, kind and text match; the count belongs to one attempt.
- **Verify:** SDD-108 coalescing case passes; the Attempts tab of two retries shows each attempt's own progress line.

#### [ ] SDD-115 — Make activity byte accounting honest

- **Requires:** SDD-108. **Requirement:** R10, R13. **Scope:** `lua/aiswarm/store.lua`, `lua/aiswarm/transport.lua`.
- **Context:** D05; a record retains `raw = rec` while only `#text + 64` is accounted.
- **Deliver:** either drop the raw payload from stored records (keep `event_id` and a reference for lookup) or account its encoded size; the 4 MiB bound then bounds actual memory. Document the choice in the store header.
- **Verify:** SDD-108 accounting case passes; a repeat of the SDD-097 flood shows the Lua heap attributable to activity records within the documented bound.

#### [ ] SDD-116 — Never notify for historical records

- **Requires:** none. **Requirement:** R10. **Scope:** `lua/aiswarm/transport.lua`, `lua/aiswarm/store.lua`, `lua/aiswarm/notify.lua`.
- **Context:** D11; `--history` telemetry replayed after the snapshot primes the notifier.
- **Deliver:** activity records carry `historical`; the notifier ignores them; the dead condition at `transport.lua:158` is removed.
- **Verify:** attach to a board whose history contains `agent.input_required`: no toast, the attention badge still reflects current state; live records after attach notify as before.

#### [ ] SDD-117 — Enforce the single notification owner

- **Requires:** none. **Requirement:** R10. **Scope:** `lua/aiswarm/notify.lua`, `lua/aiswarm/runtime/lifecycle.lua`, `bin/aiswarm` (v2 `notify`), a second editor.
- **Context:** D10; `notify.owner` is written and never read.
- **Deliver:** the owner file carries server name, pid and start identity; every channel (desktop/tmux notification in the runtime and the v2 launcher, a second editor on the same board) checks it before notifying and takes over only when the owner is dead; the health report names the current owner.
- **Verify:** two editors on one fixture board: one completion → one toast; killing the owner editor lets the other take over on the next event; the v2 launcher skips its desktop toast while an owner is alive.

#### [ ] SDD-118 — Route pause, resume and legacy actions through the canonical client

- **Requires:** none. **Requirement:** R01. **Scope:** `lua/aiswarm/ui/init.lua`, `lua/aiswarm/ui/actions.lua`, `lua/aiswarm/ui/inspector.lua` (tail/peek), `lua/aiswarm/backend.lua`.
- **Context:** D08; `P`, `:AISwarm pause` and `scheduler pause|resume` read the legacy engine's state.
- **Deliver:** pause/resume decide from `store.scheduler.paused` and call `scheduler pause|resume` (v3) or `pause|resume` (v2) through `backend.call`; `tail`, `peek` and `kill` use the backend client with the board's capabilities; no `ui/` module requires `aiswarm.legacy.ui`.
- **Verify:** on a v3 fixture, `P` twice returns dispatch to running; `:AISwarm scheduler resume` after `pause` resumes; the v2 fixture keeps its behavior; a grep shows no `legacy.ui` require under `lua/aiswarm/ui/`.

#### [ ] SDD-119 — Bind inspector row actions to the rendered tab

- **Requires:** none. **Requirement:** R08. **Scope:** `lua/aiswarm/ui/inspector.lua`.
- **Context:** D09.
- **Deliver:** every builder returns its own row map (empty for tabs without rows); `enter()` and `diff_at_cursor()` consult the map of the currently rendered tab only.
- **Verify:** open Files, press `]` to Attempts then `[` back to Overview, press `Enter` on the former file row: nothing opens; on Files the same row opens the file.

#### [ ] SDD-120 — Preserve workspace context when opening files, diffs and transcripts

- **Requires:** SDD-119. **Requirement:** R08. **Scope:** `lua/aiswarm/ui/inspector.lua`, `lua/aiswarm/ui/workspace.lua`.
- **Context:** specification §1 "reachable … without losing task selection or board context"; today these actions close the workspace and clear the read cache.
- **Deliver:** in the docked layout the file opens in the previous editing window with the workspace intact; in the floating layout the workspace hides (state retained, caches kept) and `:AISwarm` restores it on the same task, tab and scroll position; the transcript opens read-only.
- **Verify:** open a file from Files, return with `:AISwarm`: same task, same tab, no re-read (loader stats); the docked layout keeps editing windows.

#### [ ] SDD-121 — Define highlight groups when the plugin loads

- **Requires:** none. **Requirement:** R16. **Scope:** `lua/aiswarm/ui/highlights.lua`, `lua/aiswarm/init.lua`, `plugin/aiswarm.lua`.
- **Context:** groups are defined only in `workspace.open`.
- **Deliver:** `highlights.setup()` runs once on first use of any UI entry (picker, composer, results, workspace) and on `ColorScheme`; user overrides are still preserved.
- **Verify:** fresh Neovim, `:AISwarm pick` first: every `AISwarm*` group resolves; then `:AISwarm`: no redefinition of an explicitly user-defined group.

### Editor completeness

#### [ ] SDD-122 — Complete the project-switch and board-state journeys

- **Requires:** none. **Requirement:** R02. **Scope:** `lua/aiswarm/project.lua`, `lua/aiswarm/ui/project.lua`, `lua/aiswarm/ui/workspace.lua`.
- **Context:** specification §4 first use and recovery items 2, 4 and 5; audit SDD-065 row.
- **Deliver:** a `DirChanged` listener offers (never performs) the switch suggested by `project.suggestion()` through the banner and a one-key action; "open existing board" accepts a typed path with completion and validates the schema; an **invalid** board renders its own state with the diagnostic and a health action; a **reconnecting** banner shows last success age and the next retry time.
- **Verify:** `:cd` into another project shows the suggestion and leaves actions on the current board; choosing it switches with preferences kept; an invalid `board.json` fixture shows the invalid state; killing the stream shows reconnecting with a countdown that reaches zero and reconnects.

#### [ ] SDD-123 — Add output search and complete activity scoping

- **Requires:** none. **Requirement:** R08, R10. **Scope:** `lua/aiswarm/ui/inspector.lua`, `lua/aiswarm/ui/activity.lua`, `lua/aiswarm/view_state.lua`, `lua/aiswarm/ui/workspace.lua`.
- **Context:** specification §3 Output "with search", Activity "toggle task/all-attempt scope; pin scope"; §4 filters include attempt.
- **Deliver:** `/` in the Output tab searches within the bounded view and pauses following; the activity filter accepts `attempt:` and the `a` key toggles the task/all-attempt scope; the activity pane's `p` pins the feed scope and the footer says so; medium layout exposes the combined feed as an inspector tab distinct from the task's Activity tab.
- **Verify:** search moves the cursor to the match and increments unread; `attempt:<id>` shows only that attempt; `p` in the tray keeps the feed on the pinned task while the cursor moves; in a 100×30 terminal `:AISwarm activity` shows all agents.

#### [ ] SDD-124 — Replace the dependency picker with a multi-select

- **Requires:** none. **Requirement:** R09. **Scope:** `lua/aiswarm/ui/composer.lua`, `lua/aiswarm/ui/init.lua`.
- **Context:** specification §4 "multi-select picker with titles/states"; `--legacy` ignored without a range; drafts resume silently.
- **Deliver:** a Snacks picker with multi-selection showing id, state and title, writing the field once on confirm; `:AISwarm new --legacy` without a range imports the current buffer or errors explicitly; when several drafts exist the composer offers a chooser (latest by default).
- **Verify:** select three tasks, confirm: the field lists them sorted; cycles are still rejected inline; `--legacy` on a `#:` buffer imports it; two drafts show a chooser.

#### [ ] SDD-125 — Complete the overview and render reports as Markdown

- **Requires:** none. **Requirement:** R08. **Scope:** `lua/aiswarm/ui/inspector.lua`.
- **Context:** specification §3 overview "task prompt summary … and available actions"; Report tab "Markdown report".
- **Deliver:** the overview shows the first prompt lines (bounded, sanitized) and the legal actions with keys for the current target; the Report tab renders with the `markdown` filetype (treesitter when available) in a read-only buffer.
- **Verify:** overview lists exactly the actions `actions.list(target)` marks legal; a report with headings and code fences renders with Markdown highlighting; the 1 MiB report bound still holds.

#### [ ] SDD-126 — Align keys, groups and glyphs with the contracts

- **Requires:** none. **Requirement:** R07, R16. **Scope:** `lua/aiswarm/store.lua`, `lua/aiswarm/ui/workspace.lua`, `lua/aiswarm/init.lua`, `lua/aiswarm/notify.lua`, `docs/aiswarm-decisions/0004-layout-and-key-contract.md`.
- **Context:** attention group omits input-required tasks; `1-5` filter instead of jump; statusline and toasts hardcode Unicode; `ui.width/height` ignored below 120×40 without documentation.
- **Deliver:** attention includes tasks with an open input request; `1-5` behave as ADR 0004 states or the ADR is amended with the rationale; statusline and toasts use the configured icon set; the small-terminal sizing rule is documented in the ADR and help.
- **Verify:** input-required fixture appears under Attention; `3` moves the cursor to the Queued header (or the ADR records the filter semantics and the test asserts that); `icons="ascii"` yields ASCII-only statusline and toast text.

#### [ ] SDD-127 — Wire or remove dead configuration switches

- **Requires:** none. **Requirement:** R17. **Scope:** `lua/aiswarm/config.lua`, `lua/aiswarm/runtime/board.lua`, `lua/aiswarm/runtime/lifecycle.lua`, `lua/aiswarm/runtime/worker.lua`, `doc/aiswarm.txt`.
- **Context:** `telemetry.enabled/heartbeat_ms/flush_ms` and `ui.motion` are validated and never read.
- **Deliver:** heartbeat and flush intervals are board scheduler defaults (`aiswarm init --heartbeat-ms/--flush-ms`, `scheduler start` overrides) propagated to workers through their environment; the editor's `telemetry.*` values are used for health thresholds and documented as editor-side only, or removed; `ui.motion=true` animates the running glyph while the workspace is visible and stops when hidden, or the option is removed. Help documents the final ownership of every option.
- **Verify:** a board started with `--heartbeat-ms 1000` emits heartbeats at 1 s (telemetry fixture); with `motion=true` the render scheduler shows bounded animation batches that stop after `q`; no documented option is without effect.

#### [ ] SDD-128 — Release view resources and bound editor caches

- **Requires:** none. **Requirement:** R14. **Scope:** `lua/aiswarm/ui/workspace.lua`, `lua/aiswarm/ui/inspector.lua`, `lua/aiswarm/ui/tasks.lua`, `lua/aiswarm/notify.lua`, `lua/aiswarm/ui/picker.lua`.
- **Context:** audit SDD-092 row.
- **Deliver:** the health redraw timer is cancelled on close; `inspector.loaded` is an LRU bounded by bytes; `tasks._rows` drops ids absent from the store; `notify.seen` is pruned by age; the picker refreshes at most every 250 ms on health changes.
- **Verify:** `cleanup.repeated_cycles_return_to_baseline` extended with these counters returns to baseline; a 1,000-task fixture with 500 removals shrinks `_rows`; the SDD-097 flood shows a bounded picker refresh count.

#### [ ] SDD-129 — Remove synchronous work from interactive paths

- **Requires:** SDD-118. **Requirement:** R07. **Scope:** `lua/aiswarm/project.lua`, `lua/aiswarm/ui/results.lua`, `lua/aiswarm/ui/inspector.lua`, `lua/aiswarm/ui/loader.lua`.
- **Context:** audit §5.1 responsiveness row.
- **Deliver:** `git_root` is asynchronous (cached per cwd) and never blocks `root()`; results picker items are built from store metadata with asynchronous existence checks; `peek` uses the backend client; the Output tab reads only bytes appended since the last load (offset resume) and re-splits the delta.
- **Verify:** a sentinel timer proves no interaction path waits on a subprocess; the Output tab's read bytes per second are bounded by the transcript growth rate under the flood fixture.

#### [ ] SDD-130 — Deliver normalized events from the public subscribe API

- **Requires:** none. **Requirement:** R17. **Scope:** `lua/aiswarm/init.lua`, `lua/aiswarm/session.lua`, `doc/aiswarm.txt`.
- **Context:** specification §7 `subscribe(function(event) end)`; today subscribers get the engine's `(kind, payload)`.
- **Deliver:** `subscribe(fn)` delivers the normalized store change or control record on both engines; the legacy `(kind, payload)` form stays available as `subscribe_raw` for one release and is documented as deprecated.
- **Verify:** a subscriber receives identical shapes on a v2 and a v3 fixture for queue/finish; the consumer fixture in `tests/fixtures/consumer` needs no change.

#### [ ] SDD-131 — Retire the legacy UI module

- **Requires:** SDD-118, SDD-129. **Requirement:** R01. **Scope:** `lua/aiswarm/legacy/ui.lua`, `lua/aiswarm/ui/init.lua`, `tests/legacy/`.
- **Context:** the dashboard/form/picker paths are unreachable (they need Snacks, which the workspace also needs); `register_server` and statusline are triplicated.
- **Deliver:** delete `legacy/ui.lua`; keep `legacy/state.lua` as the v2 engine only; one `register_server` implementation shared by both engines; one statusline builder.
- **Verify:** `v2_lua_test` still passes against the v2 fixture through the workspace; no module references `legacy.ui`; line count of `lua/aiswarm/legacy/` drops accordingly.

### Runtime correctness

#### [ ] SDD-132 — Gate the reducer by control type and report interior corruption

- **Requires:** SDD-108. **Requirement:** R03. **Scope:** `lua/aiswarm/runtime/reducer.lua`, `lua/aiswarm/runtime/journal.lua`, `lua/aiswarm/protocol.lua`.
- **Context:** D06, D20.
- **Deliver:** the reducer applies payloads only for types in `P.CONTROL_TYPES`; unknown types are counted and exposed by `snapshot`/`doctor` as inspectable records; `J.each` reports undecodable interior lines (count, first offset) and recovery refuses to publish projections past an interior corruption without an explicit `--quarantine-from` action.
- **Verify:** SDD-108 unknown-type case passes; an interior corrupt record fixture makes `snapshot` exit 4 with the offset, `migrate --dry-run` still works read-only, and the explicit repair action quarantines from that offset.

#### [ ] SDD-133 — Quarantine whole incomplete transactions

- **Requires:** SDD-108. **Requirement:** R03. **Scope:** `lua/aiswarm/runtime/journal.lua`.
- **Context:** D07; `J.tail` reads a bounded tail.
- **Deliver:** recovery walks backwards until the start of the incomplete transaction regardless of its size (growing the tail window as needed) and quarantines every record of that `txn.id`.
- **Verify:** SDD-108 large-transaction case passes (committed sequence 1); the seven ADR 0002 crash points still recover identically.

#### [ ] SDD-134 — Guard worker lifecycle commits

- **Requires:** none. **Requirement:** R05, R11. **Scope:** `lua/aiswarm/runtime/worker.lua`, `lua/aiswarm/runtime/ops.lua`.
- **Context:** D12.
- **Deliver:** `attempt_started` commits before the provider is spawned (or the spawn is fenced so that a failed commit terminates the process group before exit); `attempt_finished` retries lock acquisition with backoff for a bounded window and, on final failure, writes the outcome to the attempt directory (`outcome.pending.json`) that reconcile publishes as the real outcome, never as "orphaned".
- **Verify:** hold the control lock for 15 s while a worker starts and while one finishes: no unsupervised provider survives, and the recorded outcome equals the provider's exit.

#### [ ] SDD-135 — Move slow work out of the control lock

- **Requires:** SDD-134. **Requirement:** R05. **Scope:** `lua/aiswarm/runtime/lifecycle.lua`, `lua/aiswarm/runtime/lock.lua`, `lua/aiswarm/runtime/util.lua`.
- **Context:** D13 and the lock-orphaning risk in `lock.lua` (identity via `ps` after `mkdir`).
- **Deliver:** worktree provisioning runs before the reservation transaction (with a second transaction recording failure); reconcile probes tmux/ps outside the lock and commits results in one short transaction; lock owner identity is captured before `mkdir`.
- **Verify:** dispatch of a worktree task holds the lock < 250 ms p95 (ADR 0001 budget) with a slow `git` stub; `lock.live_owner_never_stolen` passes with a 3 s `ps` stub.

#### [ ] SDD-136 — Make the CLI surface consistent across schemas

- **Requires:** none. **Requirement:** R01. **Scope:** `bin/aiswarm`, `runtime/cli.lua`, `lua/aiswarm/runtime/util.lua`, `lua/aiswarm/runtime/commands.lua`.
- **Context:** D14 and audit §5.2 root precedence/exit code rows.
- **Deliver:** `--root DIR` accepted by every command and by the launcher (explicit → `AISWARM_ROOT` → discovery, discovery shared by Bash and Lua); short flags `-f`, `-n N` and `--with-result` parse as documented; `aiswarm help` prints the command set of the detected schema; unknown commands exit 1 on both paths; `--format` is honored or rejected.
- **Verify:** `compat.launchers` extended: `aiswarm --root X status`, `tail T-001 -f`, `show T-001 --with-result` succeed on v3; `aiswarm help` on a v3 board lists `stream`; unknown command exits 1 in Bash and Lua.

#### [ ] SDD-137 — Schedule retention and signal every eviction

- **Requires:** none. **Requirement:** R13. **Scope:** `lua/aiswarm/runtime/retention.lua`, `lua/aiswarm/runtime/lifecycle.lua`, `lua/aiswarm/runtime/stream.lua`.
- **Context:** D15.
- **Deliver:** the scheduler runs retention on a configurable interval (default hourly) for closed segments only; evicted telemetry or raw segments produce a `gap` frame for readers positioned before the eviction; `retention.json` records per-stream marks.
- **Verify:** `retention.rotation_eviction_and_gaps` extended: after a scheduled run an old cursor receives a gap frame for both stdout and telemetry; open segments are untouched.

#### [ ] SDD-138 — Harden the worker inbox

- **Requires:** none. **Requirement:** R11. **Scope:** `lua/aiswarm/runtime/telemetry.lua`, `bin/aiswarm-progress`.
- **Context:** D16.
- **Deliver:** unreadable or rejected inbox files are moved to `inbox/rejected/` with one warning; `aiswarm-progress` validates numeric fields and encodes JSON through `jq` or the Lua runtime; accepted message ids are persisted in `activity.json` so a restarted writer does not re-emit them.
- **Verify:** a garbage `.json` in the inbox produces one warning and disappears from the scan; `--completed x` fails with exit 3; restart the writer after accepting a message: no duplicate normalized record.

#### [ ] SDD-139 — Take the control lock during migration and honor the marker everywhere

- **Requires:** none. **Requirement:** R06. **Scope:** `lua/aiswarm/runtime/migrate.lua`, `bin/aiswarm`.
- **Context:** D17.
- **Deliver:** migration acquires `locks/control.d` for its whole duration; the v2 Bash path checks `locks/migration.marker` in `with_lock` and refuses mutations with exit 3; quiescence is re-checked under the lock.
- **Verify:** `migrate.refuses_live_writer_and_scheduler` extended: a v2 `add` during migration exits 3; a concurrent v3 `add` waits or fails with the lock owner named.

#### [ ] SDD-140 — Key worktrees by board and attempt

- **Requires:** none. **Requirement:** R05. **Scope:** `lua/aiswarm/runtime/lifecycle.lua`.
- **Context:** D18.
- **Deliver:** worktree path `<dir>/<board-short>/<task-id>`; reuse requires the marker's `board_id` to match; the branch name carries the board short id.
- **Verify:** two boards on one repository each get their own `T-001` worktree; a marker from another board is refused with a structured isolation failure.

#### [ ] SDD-141 — Make compatibility kill one transaction and race outcomes truthful

- **Requires:** none. **Requirement:** R05. **Scope:** `lua/aiswarm/runtime/lifecycle.lua`, `lua/aiswarm/runtime/ops.lua`, `lua/aiswarm/runtime/commands.lua`.
- **Context:** D19.
- **Deliver:** `kill` emits cancel and retry in one journal transaction; `cancel` returns the attempt's actual terminal state when it finished during the grace wait and the CLI prints that state; reconcile applies a minimum age (startup deadline) before orphaning a `starting` attempt whose session is absent.
- **Verify:** `legacy.kill_requeues_once_on_v3` asserts one transaction; the cancel/finish race fixture prints "succeeded" and records no cancellation; reconcile between reservation and spawn leaves the attempt starting.

#### [ ] SDD-142 — Bring doctor and health to parity

- **Requires:** none. **Requirement:** R17. **Scope:** `lua/aiswarm/runtime/commands.lua`, `lua/aiswarm/health.lua`, `bin/aiswarm`.
- **Context:** audit SDD-094 row.
- **Deliver:** the CLI doctor reports stream health (last stream record age), dead push registrations, degraded telemetry (drops/gaps) and the migration manifest phase; it loads no editor module; Bash doctor treats GNU `timeout` as required only for v2 boards.
- **Verify:** `health.doctor_and_checkhealth_agree_on_real_boards` extended with the four fixtures; the headless CLI has no `aiswarm.project` in `package.loaded` after `doctor`.

#### [ ] SDD-143 — Complete cursor semantics

- **Requires:** none. **Requirement:** R12. **Scope:** `lua/aiswarm/runtime/cursor.lua`, `lua/aiswarm/runtime/stream.lua`, `lua/aiswarm/runtime/telemetry_commands.lua`.
- **Context:** audit SDD-082 row.
- **Deliver:** `--since` filters by observed time; log positions are encoded when `logs` follow is requested; a journal-generation change during `--follow` emits `gap` + fresh snapshot; a `resync_required` frame carries a usable `next_cursor`.
- **Verify:** `cursor.resume_filter_and_rejections` extended for each case; a consumer following through a generation change ends with state equal to the committed state.

#### [ ] SDD-144 — Wire the normalizer or remove its dead hooks

- **Requires:** none. **Requirement:** R11, R15. **Scope:** `lua/aiswarm/runtime/worker.lua`, `lua/aiswarm/runtime/normalize.lua`.
- **Context:** `feed()` lines discarded; `finish()`/`native()` never called.
- **Deliver:** the worker consumes `feed()` results for line counts and oversized diagnostics and calls `finish()` at exit; `native()` is either backed by an adapter registry entry that no provider enables yet (documented as such) or deleted.
- **Verify:** `worker.oversized_line_diagnostic` counts match the parser; no unreferenced function remains in `normalize.lua`.

### Release

#### [ ] SDD-145 — Retain evidence and re-run the acceptance matrix

- **Requires:** SDD-108, SDD-109, SDD-111, SDD-112, SDD-113, SDD-114, SDD-115, SDD-116, SDD-117, SDD-118, SDD-119, SDD-120, SDD-121, SDD-122, SDD-123, SDD-124, SDD-125, SDD-126, SDD-127, SDD-128, SDD-129, SDD-130, SDD-131, SDD-132, SDD-133, SDD-134, SDD-135, SDD-136, SDD-137, SDD-138, SDD-139, SDD-140, SDD-141, SDD-142, SDD-143, SDD-144. **Requirement:** R18. **Scope:** `scripts/test-aiswarm.sh`, `docs/aiswarm-evidence/`, evidence records only.
- **Context:** SDD-099 reopened; ledger artifacts deleted with the ignored `artifacts/` directory.
- **Deliver:** `--record` copies `evidence.json` (and the terminal captures of SDD-098) into `docs/aiswarm-evidence/runs/<run-id>/` so records reference versioned files; every SDD-001–107 record is re-recorded on this tree; the four suites, the benchmark and the terminal captures are re-run; unverified cells (Linux, Neovim 0.10.4, real ENOSPC, power loss) stay explicitly unverified unless an environment is available.
- **Verify:** `bash scripts/validate-aiswarm-plan.sh` (historical plan) and the remediation-plan validation both exit 0 without `--allow-missing-artifacts`; all suites pass; measured figures are within the SDD-097 and ADR 0001 budgets.

#### [ ] SDD-146 — Close core against the specification

- **Requires:** SDD-145. **Requirement:** R18. **Scope:** `docs/aiswarm-release-checklist.md`, `docs/aiswarm-implementation-audit.md`, `docs/aiswarm-implementation-sdd-plan.md`.
- **Deliver:** every audit defect D01–D20 and §5 row maps to a passing card or a decision record; the checklist reconciles requirement rows with retained evidence; the historical plan's SDD-099/100 are checked only from these records; README and help describe the shipped behavior without the "remediation pending" caveats.
- **Verify:** the demonstration `scripts/aiswarm-demo.sh` completes; `docs.help_tags_and_links_resolve` passes; no P0/core defect remains open; no commit or publication is implied by this document.

## 4. Audit finding closure map

| Audit defect | Owning task |
|---|---|
| D01 loader cache | SDD-111 |
| D02 cross-board targets | SDD-112 |
| D03 per-attempt bound | SDD-113 |
| D04 attempt-aware coalescing | SDD-114 |
| D05 byte accounting | SDD-115 |
| D06 unknown control types | SDD-132 |
| D07 incomplete-transaction quarantine | SDD-133 |
| D08 dispatch resume on v3 | SDD-118 |
| D09 inspector row targeting | SDD-119 |
| D10 notification owner | SDD-117 |
| D11 historical toasts | SDD-116 |
| D12 unguarded worker commits | SDD-134 |
| D13 lock scope | SDD-135 |
| D14 legacy CLI spellings | SDD-136 |
| D15 retention/gaps | SDD-137 |
| D16 inbox robustness | SDD-138 |
| D17 migration lock/marker | SDD-139 |
| D18 worktree keying | SDD-140 |
| D19 kill/race/reconcile | SDD-141 |
| D20 interior corruption | SDD-132 |
| §5.1 rows | SDD-120–SDD-131 as named per row |
| §5.2 rows | SDD-135, SDD-136, SDD-142, SDD-143, SDD-144 |
| §5.3 rows | SDD-109, SDD-145, SDD-146 |

## 5. Start sequence

Start with **SDD-108** (failing tests) and **SDD-109** (documentation) in the same review unit, then the probe-backed fixes **SDD-111–SDD-115**, **SDD-132**, **SDD-133**, then **SDD-118** and **SDD-134** (the two defects a user meets first: unresumable dispatch and a lost worker outcome). Editor completeness and the remaining runtime cards can proceed in parallel. **SDD-145** closes only when evidence lives in the repository.
