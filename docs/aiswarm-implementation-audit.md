# aiswarm implementation audit

Status: **current** · Date: 2026-09-14 · Baseline: working tree on top of `272c5aa` (uncommitted standalone package) · Companion: [remediation SDD plan](aiswarm-remediation-sdd-plan.md)

This audit answers one question: **was the [implementation SDD plan](aiswarm-implementation-sdd-plan.md) implemented as the [UX technical specification](aiswarm-ux-technical-spec.md) requires?** It records what exists, what the automated suites prove, and every gap confirmed by reading the code, by running the audit probes, or by the two structured reviews (runtime and UI) performed for this document. The historical 32 baseline findings live in the [baseline audit archive](aiswarm-baseline-audit.md); their closure is re-examined here only where the current code still shows the same behavior.

## 1. Verdict

The plan is **substantially implemented but not release-certifiable**.

| Area | Finding |
|---|---|
| Code | All 100 core cards have production code and tagged test cases. The standalone package, v3 board runtime (journal, attempts, scheduler, cancel/retry, migration), worker telemetry, stream/ack/logs, the responsive workspace, composer, activity feed, notifications, health and statusline exist and work in the mock pipeline. |
| Automated proof | `bash scripts/test-aiswarm.sh --suite core` on this tree: **227 passed, 1 failed, 0 unverified** (140 s). The failure is `docs.help_tags_and_links_resolve`: README linked this audit and the remediation plan before either existed. |
| Evidence | `bash scripts/validate-aiswarm-plan.sh` reports every SDD-089–099 record pointing at **nonexistent artifacts**: the run directories under `artifacts/` were deleted and the directory is ignored. Historical checkmarks in the plan cannot be re-certified from the repository alone, which is why the plan header reopened SDD-099/100. |
| Probes | `tests/audit/implementation_probe.lua` (re-run today, `docs/aiswarm-evidence/audit/2026-09-14-probes.json`) reproduces **seven defects** in shipped behavior (§4, D01–D07). None is covered by a failing test. |
| Specification | About 30 further deviations from §3–§8 of the specification and from ADR 0002–0004 are listed in §5. Most are partial cards that passed their narrower tests. |
| Documentation | README and `:help aiswarm` already disclose several of these limits, but link to documents that did not exist, omit shipped subcommands, cite commands that do not exist, and the release checklist still says every requirement "passed". |

Nothing in the old plugin name remains in the code (`grep -ri hive` finds only the word "archive"). Three words mangled by the rename ("arcaiswarm") were corrected in the specification and plan while writing this audit.

## 2. Method

1. Full read of `bin/`, `runtime/`, `lua/aiswarm/**`, `plugin/`, `doc/`, `examples/`, `scripts/` and both design documents.
2. `bash scripts/test-aiswarm.sh --suite core` (run `20260914T165436Z-99745`), `bash scripts/validate-aiswarm-plan.sh`, and `nvim -l tests/audit/implementation_probe.lua`.
3. Two independent structured reviews, one for the backend/runtime (SDD-017–043, 069–094; spec §5/§6/§8) and one for the client/UI (SDD-009–016, 044–068, 088–096; spec §3/§4/§7), each producing card-by-card verdicts with `file:line` evidence.
4. Every high-impact claim below was confirmed by a second reading of the cited lines or by a targeted `nvim -l` experiment.

Line numbers refer to this tree; they will drift after remediation and are intended as anchors, not identifiers.

## 3. Module map (current)

| Path | Lines | Responsibility | Verified by |
|---|---|---|---|
| `bin/aiswarm` | 767 | Launcher: root discovery, schema detection, v2 Bash board implementation, hand-off of v3 boards to `runtime/cli.lua` | compat/legacy suites |
| `bin/aiswarm-push`, `bin/aiswarm-progress` | 13, 29 | Push bridge to a registered editor; worker inbox helper | compat.push, telemetry.worker |
| `runtime/cli.lua`, `runtime/worker.lua` | 47, 12 | Clean headless entry points (bundled modules only) | foundation.runtime_spike, telemetry.worker |
| `lua/aiswarm/runtime/{board,journal,reducer,lock,ops,lifecycle}.lua` | 265, 154, 22, 97, 311, 524 | Board manifest, write-ahead journal, projections, owned locks, validated mutations, dispatch/scheduler/cancel/reconcile | lifecycle.* suites |
| `lua/aiswarm/runtime/{worker,telemetry,telemetry_commands,stream,cursor,frames,normalize,retention,briefing}.lua` | 265, 161, 185, 269, 56, 65, 79, 75, 51 | Worker supervision, per-attempt telemetry writer/inbox, stream multiplexer, cursors, frame codec, normalization, retention, briefings | telemetry.* suites |
| `lua/aiswarm/runtime/{tmux,util,compat,migrate,commands}.lua` | 105, 150, 146, 421, 206 | Board-scoped tmux, helpers, legacy command translation, migration, command registry | lifecycle, compat, migration suites |
| `lua/aiswarm/{protocol,config,project,session,backend,adapter,store,view_state,transport,notify,health,init,commands}.lua` | 327, 96, 110, 34, 98, 92, 265, 73, 341, 84, 85, 131, 88 | Shared validators, configuration, project sessions, engine selection, async CLI client, v2 adapter, normalized store, selection model, v3 stream transport, notification policy, health, public API, `:AISwarm` | workspace, telemetry, compat, release suites |
| `lua/aiswarm/ui/*.lua` | 2,506 total | Workspace shell, layout, task list, inspector, activity, composer, actions, pickers, project/migrate views, render scheduler, text primitives, highlights, async loader | workspace.*, terminal.screens |
| `lua/aiswarm/legacy/{state,ui}.lua` | 290, 441 | v2 polling engine and the pre-workspace UI; still the only implementation of `tail`, `peek`, `kill` and dispatch pause from the editor | legacy.v2_lua |
| `tests/` | 34 files | Runner, sandbox, fixtures, suites tagged by SDD card | — |

## 4. Confirmed defects

Each defect names the observable behavior, the specification clause it violates, the code, the evidence, and the remediation card that owns it.

| ID | Defect | Spec / ADR | Code | Evidence | Card |
|---|---|---|---|---|---|
| D01 | **Loader cache ignores read parameters.** The cache key is `path:mtime:size`; a tail read after a head read (or a 64 KiB picker preview before a 2 MiB Output read) returns the earlier bytes. | §3 Output tab "bounded, streaming" | `lua/aiswarm/ui/loader.lua:38-39` | Probe `tail_read == "HEAD\n"`; `uv.fs_read` with an offset returns the tail when called directly | SDD-111 |
| D02 | **Action targets are not board-scoped.** `revalidate` compares task revision/state only; a target captured before `:AISwarm project open` executes against a same-ID task on the new board. | §4 "Actions bind to `{board_id, task_id, attempt_id, expected_revision}`" | `lua/aiswarm/ui/actions.lua:99-106` | Probe `cross_board_target_accepted == true` | SDD-112 |
| D03 | **Per-attempt activity bound is counted, never enforced.** 500 records/attempt is declared; 600 are kept. | §6 "500 records per selected attempt" | `lua/aiswarm/store.lua:6,132-135` | Probe `per_attempt_records == 600` | SDD-113 |
| D04 | **Activity coalescing ignores attempt identity.** Identical text from two attempts of one task merges into one record with a count. | §6 "Attempt identity prevents misattribution during retries" | `lua/aiswarm/store.lua:123` | Probe `distinct_attempts_coalesced_to_records == 1` | SDD-114 |
| D05 | **Activity byte bound is not honest.** Accounting counts `#text + 64` while the record retains the full raw telemetry payload (`raw = rec`). A 60 KiB payload is accounted as 65 bytes; the 4 MiB bound can hold ~1000× more. | §6 "2,000 records/4 MiB globally" | `lua/aiswarm/store.lua:121`, `lua/aiswarm/transport.lua:76` | Probe `accounted_bytes_for_60k_payload == 65`; SDD-097 record shows editor RSS 240 MiB | SDD-115 |
| D06 | **Reducer applies unknown control types.** Any record whose payload carries `task`/`attempt`/`scheduler`/`board` mutates projections regardless of `type`; the comment "unknown types change nothing" and the protocol comment are both false. | §6 "Unknown event types remain inspectable without changing task state" | `lua/aiswarm/runtime/reducer.lua:7-12`, `lua/aiswarm/protocol.lua:235` | Probe `unknown_event_changes_task == true` | SDD-132 |
| D07 | **Recovery quarantines only the part of an incomplete transaction that fits the tail buffer.** A 100-record uncommitted transaction (~2 KiB per record) leaves records 2–71 treated as committed. | ADR 0002 step 1 "every trailing record of that `txn.id` is quarantined" | `lua/aiswarm/runtime/journal.lua:64-107` (`J.tail` is bounded) | Probe `incomplete_large_transaction_committed_seq == 71`, expected 1 | SDD-133 |
| D08 | **Dispatch cannot be resumed from the editor on a v3 board.** `P`, `:AISwarm pause` and `:AISwarm scheduler pause\|resume` call the legacy toggle, which reads `legacy.state.meta.paused`; under the v3 transport that table is empty, so the command sent is always `pause`. | §4 "`P` toggle dispatch pause"; §4 scheduler commands | `lua/aiswarm/ui/init.lua:44-50`, `lua/aiswarm/legacy/ui.lua:57-63` | By inspection (both reviews) | SDD-118 |
| D09 | **Inspector `Enter`/`d` use a stale row map across tabs.** `M.rows` is rebuilt only by the Files and Attempts builders; on Overview/Activity/Output/Report the previous tab's rows remain, so `Enter` can open a file or select an attempt from a row that is no longer displayed. | §3 inspector tabs | `lua/aiswarm/ui/inspector.lua:266,284,406-424` | By inspection; already listed under "inspector row targeting" in `:help aiswarm-limits` | SDD-119 |
| D10 | **Notification owner is written, never read.** `notify.owner` is claimed by the editor but no worker, scheduler, launcher or second editor consults it; desktop/tmux and editor toasts can duplicate. | §4 "One notification owner is selected for a given local user session" | `lua/aiswarm/notify.lua:79-82`; no reader in `lua/`, `bin/`, `runtime/` | `grep -rn notify.owner` | SDD-117 |
| D11 | **Historical telemetry can toast on attach.** Stream frames replayed with `--history 200` arrive after the snapshot primes the notifier; telemetry frames are applied unconditionally (`if not frame.historical or true`), so a historical `agent.input_required` record raises a notification. | §4 "No historical toast replay when attaching" | `lua/aiswarm/transport.lua:157-158`, `lua/aiswarm/notify.lua:64-73` | By inspection | SDD-116 |
| D12 | **Worker lifecycle commits are unguarded.** The provider is spawned before `attempt_started` commits; a lock timeout (`error{code=4}`) aborts the worker and leaves a detached provider running. `attempt_finished` is likewise unguarded, so contention turns a real exit into a later "orphaned". | §5 "Dispatch reservation and spawn failure must terminate/release the reserved attempt atomically" | `lua/aiswarm/runtime/worker.lua:187-195,256`, `lua/aiswarm/runtime/lock.lua:90` | By inspection | SDD-134 |
| D13 | **Control lock held across slow work.** `prepare_cwd` (git worktree add) runs inside the dispatch transaction; reconcile runs `tmux`/`ps` per running attempt under the lock every tick. All reads and worker commits wait. | ADR 0002 transaction order; ADR 0001 budget "≤250 ms p95 control command" | `lua/aiswarm/runtime/lifecycle.lua:121,207-208`, `lua/aiswarm/runtime/util.lua:101` | By inspection | SDD-135 |
| D14 | **Legacy CLI spellings advertised by help do not parse on v3 boards.** `-f`, `-n N` and `--with-result` are treated as positionals or "missing value". | §8 "Existing CLI command spellings may remain … with explicit semantics" | `lua/aiswarm/runtime/util.lua:124-148`, `lua/aiswarm/runtime/commands.lua:196` | Verified with `nvim -l` by the runtime review | SDD-136 |
| D15 | **Retention never runs by itself; evicted telemetry yields no gap frame.** Only manual `aiswarm retention` prunes 7-day history; a reader whose telemetry file was evicted returns silently. `retention.json` is overwritten per segment, losing the other stream's mark. | §6 "readers see an explicit gap after eviction" | `lua/aiswarm/runtime/telemetry_commands.lua:177`, `lua/aiswarm/runtime/stream.lua:123-128`, `lua/aiswarm/runtime/retention.lua:37` | By inspection | SDD-137 |
| D16 | **Unreadable inbox files are never removed** and are rescanned every 250 ms forever; `bin/aiswarm-progress` can produce them (unvalidated `--completed/--total`, hand-rolled JSON escaping). Inbox dedup is in-memory only. | §6 "atomic spool/inbox"; SDD-075 "partial spool files are ignored/recovered" | `lua/aiswarm/runtime/telemetry.lua:127-142`, `bin/aiswarm-progress:21-24` | By inspection | SDD-138 |
| D17 | **Migration takes no control lock and the v2 launcher ignores the migration marker.** | ADR 0002 "Migration acquires the same lock"; §8 "Compatibility wrapper clients honor the migration marker" | `lua/aiswarm/runtime/migrate.lua:233`, `bin/aiswarm:82-95` | By inspection; README already says "concurrent-writer protection still needs remediation" | SDD-139 |
| D18 | **Worktree reuse is keyed by task ID only.** Two boards on one repository share `T-001`'s worktree; reuse validates the git common dir, not the board id in the marker file. | SDD-030 "retry cannot accidentally reuse an unrelated board's worktree" | `lua/aiswarm/runtime/lifecycle.lua:45-58` | By inspection | SDD-140 |
| D19 | **Legacy `kill` is two transactions; a cancel that races a finish reports "cancelled" for a succeeded attempt; reconcile can orphan a `starting` attempt between reservation and spawn.** | SDD-037 "one serialized compatibility operation"; SDD-033 "cancel/finish race yields one terminal result" | `lua/aiswarm/runtime/lifecycle.lua:304-311,280-300,209-215`, `lua/aiswarm/runtime/commands.lua:121` | By inspection | SDD-141 |
| D20 | **Interior journal corruption is skipped silently.** `J.each` decodes what it can; an undecodable interior line is dropped without a diagnostic. | SDD-022 "corrupt interior records are not silently skipped" | `lua/aiswarm/runtime/journal.lua:136` | By inspection | SDD-132 |

## 5. Specification deviations by area

Cards marked **partial** passed their automated cases; the deviation is between the card's test and the specification text.

### 5.1 Workspace, inspector, activity (spec §3, §4; ADR 0004)

| Card | Gap | Code |
|---|---|---|
| SDD-050 | Highlight groups are defined only when the workspace opens; `:AISwarm pick`, `new` or `results` as the first action render without colors. Spinner glyphs exist but nothing animates; `ui.motion` is validated and never read. | `ui/workspace.lua:344`, `ui/text.lua:5`, `config.lua:64` |
| SDD-051 | Attention group contains failed tasks only; input-required tasks stay in Running. | `store.lua:189-194` |
| SDD-053 | `1-5` are group *filters*; ADR 0004 says "jump to group". `ui.width/height` are ignored below 120×40 (undocumented). | `ui/workspace.lua:102-104`, `ui/layout.lua:21-22` |
| SDD-055 | Overview lacks the prompt summary and the list of available actions. | `ui/inspector.lua:114-166` |
| SDD-056 | Output has no search (`view_state.output.search` is never used). | `view_state.lua:11` |
| SDD-057 | Report is plain text with `#` lines highlighted, not a Markdown preview. | `ui/inspector.lua:233` |
| SDD-062 | Dependency picker is a repeated single-select `vim.ui.select`, not a multi-select with titles/states. | `ui/composer.lua:340-360` |
| SDD-064 | `:AISwarm new --legacy` without a range silently ignores the flag; reopening always resumes the latest draft with no chooser. | `ui/init.lua:21`, `ui/composer.lua:269-272` |
| SDD-065 | No project-switch prompt on `:cd` (no `DirChanged` autocmd; suggestion only under `:AISwarm project show`); "open existing board" offers no path entry; an **invalid** board renders as an empty ready workspace; "reconnecting" has no banner and `retry_at` is never shown. | `project.lua:104`, `ui/project.lua:16-17,33-42`, `ui/workspace.lua:133-185` |
| SDD-066 | Activity filter has no `attempt:` token; the task/all-attempt scope toggle (`feed.scope_all_attempts`) has no key; `pin_scope` is unbound while the footer says "p pin" (`p` pins the inspector instead). Medium layout has no combined all-agents feed: `:AISwarm activity` opens the selected task's Activity tab. | `ui/activity.lua:82-102`, `ui/workspace.lua:80-83,285`, `ui/init.lua:24-27` |
| SDD-052/059 | Opening a file, a diff or the full transcript closes the workspace and clears the inspector cache. | `ui/inspector.lua:390,419,433,435,448` |
| SDD-095 | Statusline and toasts hardcode Unicode glyphs regardless of `icons="ascii"`. | `init.lua:91-93`, `notify.lua:42-46` |
| SDD-092 | `_health_timer` survives close; `inspector.loaded`, `tasks._rows` and `notify.seen` never evict; the picker re-runs its finder on every `health` emit (one per telemetry record). | `ui/workspace.lua:239`, `ui/inspector.lua:71`, `ui/tasks.lua:130`, `notify.lua:31`, `ui/picker.lua:99-104` |
| §1 Responsiveness | Synchronous work reachable from interaction: `project.git_root` waits up to 2 s (lazily from `init.root()`); legacy `peek` waits up to 2×1.5 s; results picker stats every attempt synchronously; the Output tab re-reads and re-splits the whole 2 MiB tail at least once per second while a task runs. | `project.lua:44`, `legacy/ui.lua:77-95`, `ui/results.lua:15-18`, `ui/inspector.lua:318` |
| §7 API | `require("aiswarm").subscribe(fn)` delivers the engine's `(kind, payload)` pairs, not the normalized event the specification shows. `telemetry.enabled/heartbeat_ms/flush_ms` are validated and never used (workers read `AISWARM_FLUSH_MS`/`AISWARM_HEARTBEAT_MS`; snapshot hardcodes 5000). | `init.lua:107`, `runtime/worker.lua:212`, `runtime/commands.lua:125` |
| §8 Identity | Messages cite `:AISwarmKill` and `:AISwarmTail`, commands that do not exist; the specification and plan also use `AISwarmKill` as a command name although §8 forbids prefixed commands. | `ui/init.lua:37`, `legacy/ui.lua:43`, spec §4, plan SDD-037 |

### 5.2 Runtime, protocol, migration (spec §5, §6, §8; ADR 0001–0003)

| Card | Gap | Code |
|---|---|---|
| SDD-022 | Rebuild removes stale task projections but not stale attempt projections. | `runtime/board.lua:121` |
| SDD-019 | Owner identity spawns `ps` (2 s timeout) *after* `mkdir` while `ORPHAN_MS` is 2 s: a slow `ps` makes a live lock look orphaned. | `runtime/lock.lua:6,52-56`, `runtime/util.lua:101` |
| SDD-069 | Missing Neovim is detected after reservation and recorded as a failed attempt, not "before a phantom running task". | `runtime/lifecycle.lua:188` |
| SDD-074 | The normalizer's `feed()` results are discarded by the worker; `finish()` and `native()` are never called. Raw output/preview records are correct. | `runtime/worker.lua:199-200`, `runtime/normalize.lua` |
| SDD-079 | `logs --follow` stalls silently when a segment shrinks or is replaced; imported legacy attempts keep stdout at `logs/<id>.log`, so `logs` reports "absent" while `tail` works. | `runtime/telemetry_commands.lua:104-107,126-129`, `runtime/migrate.lua:182` |
| SDD-082 | No `--since` filter; cursor `logs` positions are always empty; a journal-generation change is checked only at connect; a `resync_required` gap carries `next_cursor=""`; `--format` is accepted and ignored. | `runtime/telemetry_commands.lua:48-51`, `runtime/cursor.lua:17`, `runtime/stream.lua:72-76,212,217` |
| SDD-094 | CLI doctor lacks stream health, dead push-registration and degraded-telemetry checks, reports migration only as "marker present", and loads the editor module `aiswarm.project` inside the headless CLI. Bash doctor fails on a missing GNU `timeout` even for v3 boards. | `runtime/commands.lua:32-56`, `bin/aiswarm:682-689` |
| §6 control types | `task.blocked` is never emitted (blockers are derived at snapshot); `board.initialized` is declared but never written; `task.reordered/retried/imported/finished`, `attempt.reserved`, `board.migrated` are additive extras. | `runtime/board.lua:195`, `protocol.lua:14` |
| §8 root precedence | The launcher has no `--root` (only `init` accepts it); `runtime/cli.lua` reads `AISWARM_ROOT` or `cwd/.aiswarm` without ancestor discovery; `bin/aiswarm:58` is a dead reassignment; `aiswarm help` prints the v2 usage even on a v3 board (handled before schema detection). | `runtime/cli.lua:30`, `runtime/commands.lua:26`, `bin/aiswarm:58,723-728` |
| Exit codes | Bash prints usage and exits 0 on an unknown command; the Lua runtime exits 1. | `bin/aiswarm:763`, `runtime/cli.lua:26` |
| Memory | The stream reads whole telemetry files to find checkpoints and whole deltas; history mode and `briefing` replay every attempt from sequence 0; migration checksums load whole logs; `seen_messages` grows without bound; `state.json` is rewritten per commit. | `runtime/stream.lua:107,131,225-228`, `runtime/telemetry_commands.lua:166-170`, `runtime/migrate.lua:20-24,205`, `runtime/telemetry.lua:131`, `runtime/board.lua:105` |
| Error handling | Module registration is wrapped in `pcall`, so a syntax error in lifecycle/telemetry/migrate surfaces as "unknown command"; pipe read errors and writer drop counts are ignored; tmux `set-option` results ignored. | `runtime/commands.lua:201-204`, `runtime/worker.lua:199-200`, `runtime/telemetry.lua:40`, `runtime/tmux.lua:63-66` |
| Duplication | Context templates, prompt rendering, provider argv, doctor and the provider id list exist in both the Bash v2 path and the Lua runtime; the inbox message is built by both `bin/aiswarm-progress` and `report-event`. The rendered prompt is passed as an argv element (visible in `ps`, subject to `ARG_MAX`). | `bin/aiswarm:170-362`, `runtime/worker.lua:21-74`, `providers/registry.lua:75-90` |
| v2 path | The unchanged v2 implementation still names sessions `agent-<id>` and `down` kills every `agent-*` session on the tmux server (baseline finding A10 remains true for legacy boards). | `bin/aiswarm:412-418,629-636` |

### 5.3 Documentation and evidence (spec §8; SDD-096, 099, 100)

- README, `:help aiswarm-limits`, the plan header and the baseline audit linked `aiswarm-implementation-audit.md` and `aiswarm-remediation-sdd-plan.md`, which did not exist until this commit (core suite failure).
- `:help aiswarm-commands` omits the shipped `tail`, `peek`, `kill` and `pause` subcommands; README refers to a which-key example that `examples/` does not contain.
- `docs/aiswarm-release-checklist.md` states every requirement "passed" while the plan header reopened SDD-099/100 and the validator cannot find the cited artifacts.
- The ledger's SDD-089–099 records cite artifact paths that no longer exist; SDD-099 also leaves Linux, Neovim 0.10.4, real ENOSPC and power loss unverified.
- The three "arcaiswarm" typos in spec §6/§8 and plan SDD-084 were fixed with this audit; `lua/aiswarm/config.lua:90` still carries a comment left by the rename ("AISWARM_PROVIDER → AISWARM_PROVIDER").

## 6. What is verified and can be relied on

- **Identity and lifecycle**: unique attempts with disjoint artifact paths, revision-checked edits, dependency validation with visible blockers, numeric queue order, board-scoped tmux sessions (`aiswarm-<board>-<attempt>`), one scheduler per board, cancel without requeue, retry into a fresh attempt, report quality per attempt (lifecycle suites: 50+ cases).
- **Durability (process-crash scope)**: committed sequence allocation from the journal, tail quarantine, sidecar/applied reconciliation, fault-injected restarts at every ADR 0002 crash point except the incomplete-large-transaction case (D07).
- **Telemetry pipeline**: clean worker bootstrap, batched raw capture, heartbeats, inbox progress, per-attempt journals, frame codec, multiplexed stream with fs-event/poll fallback, composite cursors, independent acks, durable subprocess consumer, briefings; measured end-to-end (SDD-093, SDD-097: p95 flushed→visible 291 ms, →consumer 303 ms) on macOS arm64.
- **Workspace**: single instance, responsive breakpoints per ADR 0004 with real-terminal captures at five sizes, selection by identity through reorders, cancellable inspector reads, bounded output view, attempt-bound reports, live picker, prompt-first composer with drafts and inline diagnostics, notification burst aggregation.
- **Compatibility**: one namespace, canonical environment precedence, v2 boards readable through the same package, migration with verified backup, staged publication, resume and rollback.

## 7. How to reproduce this audit

```sh
bash scripts/test-aiswarm.sh --suite core                       # 227/1/0 on this tree before the docs fix
bash scripts/validate-aiswarm-plan.sh                            # artifact problems for SDD-089..099
nvim --clean --headless -u NONE -i NONE -n -l tests/audit/implementation_probe.lua
```

The probe output is archived at `docs/aiswarm-evidence/audit/2026-09-14-probes.json`. The remediation plan turns each probe into a failing regression test before the corresponding fix (SDD-108).
