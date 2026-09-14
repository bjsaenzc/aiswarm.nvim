# aiswarm implementation SDD plan

Status: **Historical implementation ledger; release acceptance reopened on 2026-09-14.** Before this review, SDD-001–100 were checked despite missing artifacts and incomplete acceptance coverage. Remaining checkmarks record historical claims, not a fresh certification. SDD-099/100 are reopened below. The [current audit](aiswarm-implementation-audit.md) and [remediation plan](aiswarm-remediation-sdd-plan.md) govern remaining work.

The standalone replacement decision supersedes transitional package aliases in this plan. Cards involving identity are restated below for the canonical package; their historical evidence must not be interpreted as evidence for the revised contract.

Source: [aiswarm UX technical specification](aiswarm-ux-technical-spec.md) and [AISwarm code audit](aiswarm-baseline-audit.md). Plan baseline: `a734168`, 2026-09-13. The source specification retains its original audit baseline `c7c636a`.

SDD means **specification-driven development** here: requirement → contract/example → implementation → observable verification → recorded evidence. This document retains original requirement/task IDs; current implementation status is assessed in the linked audit.

## 1. Execution rules

Each numbered task delivers one independently reviewable behavior, contract, or acceptance result. Its implementation and relevant verification belong in the same review unit. Dependencies must pass before a task is marked ready. Fixtures can unblock UI work before the production stream exists; a fixture-backed view is not complete end-to-end telemetry.

For each task:

1. Read the referenced requirement and dependencies. Write down the observable expectation before changing implementation.
2. Add a failing regression/contract test when the behavior warrants it. For documentation, mappings and appearance, use focused checks or a specified manual script instead of tests that merely mirror the code.
3. Implement only the task's stated scope. Keep incomplete paths unreachable or explicitly capability-gated; do not expose partially migrated write operations.
4. Run the task verification and affected contracts. Record command, exit status, environment/version, observed result and artifact location against the task ID.
5. Mark the checkbox complete only when the stated verification passes. A test skipped for unavailable tmux, platform or provider is recorded as **unverified**, never passed.

“Atomic” describes a coherent change with a single acceptance boundary, not a line-count limit. If a card requires unrelated changes or cannot be reviewed as one behavior, split it into suffixed child tasks (for example `SDD-024a`), preserve its requirement/dependency links, and mark the parent complete only after all children pass. A phase is not itself an implementation task. Acceptance-gate tasks only collect/execute evidence; defects discovered there become separate repair tasks.

No task authorizes operating a user's live board, killing unrelated tmux sessions, or running paid provider tests. All deterministic checks use disposable boards, fake provider executables and a dedicated test tmux socket. The plan itself does not install, rename or start anything.

### Verification convention

SDD-001 creates the **proposed** repository-level runner, stable across the plugin rename:

```sh
bash scripts/test-aiswarm.sh --task SDD-023
bash scripts/test-aiswarm.sh --suite core
bash scripts/test-aiswarm.sh --suite compatibility
bash scripts/test-aiswarm.sh --suite reliability
bash scripts/test-aiswarm.sh --suite performance
```

Until SDD-001 exists, these are planned commands. `--task` selects meaningful cases tagged to an ID; it fails for unknown IDs or empty automated selections. Manual/design tasks use the review procedure in their card and save an evidence record instead. Do not create a passing no-op test just to satisfy an ID. The core suite includes every core task's automated cases; manual evidence and platform coverage are additional release requirements.

Use `P` below for this standalone repository root. Paths under `P` name intended implementation ownership, not mandatory filenames if a better split is justified. New modules remain proposed until their task creates them. Test fixtures live in `P/tests/`; evidence lives in ignored `artifacts/aiswarm/<run-id>/`. Keep small durable reference fixtures and scenario definitions in version control; avoid committing generated boards, transcripts or personal machine paths.

An evidence record contains: task ID, status, commit, runner command/manual procedure, relevant tool versions, fixture/scenario, expected result, actual result, and artifact paths. No estimated dates are assigned before the runtime/durability spikes establish feasibility.

## 2. Requirement traceability

The specification is authoritative for behavior and numerical limits. These labels make task references compact. Task ranges in this document are inclusive.

| Requirement | Source and acceptance focus | Owning tasks |
|---|---|---|
| R01 Brand/compatibility | Spec §§4, 8: canonical name, environment precedence, one runtime, distinct keys | SDD-002, SDD-009–016, SDD-037, SDD-043, SDD-045, SDD-090, SDD-096 |
| R02 Project/first use | Spec §4: explicit root selection, missing/empty/offline states, initialization and scheduler actions | SDD-015, SDD-018, SDD-029, SDD-042, SDD-065 |
| R03 Persistence | Spec §§5–6: schema, locks, committed control order, projection recovery | SDD-005–006, SDD-017–024 |
| R04 Queue/dependencies | Spec §§4–5: validation, revision checks, numeric order and visible blocking | SDD-023–026, SDD-031, SDD-062 |
| R05 Attempts/isolation | Spec §5: immutable attempt evidence, board ownership, lifecycle, worktrees | SDD-027–036, SDD-055, SDD-059, SDD-071 |
| R06 Migration | Spec §8: dry run, quiescence, backups, import, staged publication, recovery | SDD-038–043 |
| R07 Workspace | Spec §3: persistent panes, stable selection, responsive dimensions and editor layout | SDD-007, SDD-044–053, SDD-060, SDD-068 |
| R08 Inspector/actions | Spec §§3–4: async reads, contextual IDs, output/report/files/attempts and legal actions | SDD-052, SDD-054–060, SDD-068 |
| R09 Composer | Spec §4: prompt first, provider/isolation, advanced fields, durable drafts, atomic submit | SDD-061–065 |
| R10 Activity/notifications | Spec §§3–4: filtered/pinned feed, unread counts, provenance, no toast storms | SDD-055–056, SDD-066–067, SDD-089 |
| R11 Worker telemetry | Spec §6: clean runtime, output, heartbeat, progress inbox and latest projection | SDD-003–004, SDD-069–077, SDD-089, SDD-093 |
| R12 Replay/consumer | Spec §6: ordering, bootstrap, cursors, independent ack, genuine process delivery | SDD-006, SDD-078–083, SDD-086–088, SDD-090–091, SDD-093, SDD-106 |
| R13 Bounds/retention | Spec §6: batching, finite queues, rotation, explicit gaps and storage degradation | SDD-048, SDD-056, SDD-066, SDD-070, SDD-073–074, SDD-078–079, SDD-084–085 |
| R14 Lifecycle cleanup | Spec §§6–7: generation checks, reconnect/backoff, no obsolete jobs/watchers | SDD-015, SDD-044–045, SDD-088, SDD-091–092 |
| R15 Provider capabilities | Spec §6: registry, raw fallback, versioned adapters, truthful usage/input | SDD-016, SDD-074, SDD-094, SDD-101–107 |
| R16 Accessibility | Spec §3: semantic theme groups, text states, Unicode cells, ASCII and reduced motion | SDD-007, SDD-050, SDD-053, SDD-098 |
| R17 Integration/package | Spec §§7–8: cached statusline, health, help, ignores, real license notices | SDD-008, SDD-013–014, SDD-094–096 |
| R18 Release evidence | Spec §§1, 9: precise latency/load, UX, crash/platform matrix and release boundaries | SDD-001–008, SDD-043, SDD-068, SDD-093, SDD-097–100 |

## 3. Delivery order and gates

| Work package | Tasks | Completion boundary |
|---|---|---|
| Foundation | SDD-001–008 | Test isolation, known baseline, explicit contracts and runtime feasibility evidence. Runtime-dependent work waits for SDD-004; durable storage work waits for SDD-005. |
| Compatibility | SDD-009–016 | The canonical package operates on a v2 fixture; data stays in place. Final cross-version verification occurs in SDD-043. |
| Lifecycle | SDD-017–037 | Validated v3 writes, unique attempts, scoped process control and correct cancel/retry semantics. |
| Migration | SDD-038–043 | Existing boards migrate with verified backup/recovery and compatibility behavior. |
| Workspace | SDD-044–068 | Complete keyboard UX using deterministic state/stream fixtures. Production telemetry remains gated. |
| Live telemetry | SDD-069–093 | Workers → journals → stream → editor and durable external consumer, including recovery and bounds. |
| Core release | SDD-094–100 | Health/integrations/docs and all required measurements/manual/platform evidence. |
| Optional integrations | SDD-101–107 | Independently tested native provider/input/runtime capabilities; not required to claim generic core telemetry. |

These packages refine the six phases in spec §9 rather than changing their scope. Specifically, headless runtime feasibility is pulled into Foundation, and core packaging is a release prerequisite even though optional provider richness remains later.

Within a package, only the card's explicit dependencies constrain order. Cross-package dependencies are intentional: UI cards may consume fixed fixtures while production collection is built later. Do not interpret this as an instruction to launch parallel agents.

There are **100 core tasks and 7 optional integration tasks**. The final core gate requires all SDD-001–099, not only the shortest dependency chain.

## 4. Atomic task backlog

### Foundation: contracts and reproducible checks

#### [x] SDD-001 — Create an isolated test entry point

- **Requires:** none. **Requirement:** R18. **Scope:** `scripts/test-aiswarm.sh`, `P/tests/runner.lua`, test sandbox helpers.
- **Deliver:** task/suite selection, assertions and exit reporting; discover the current plugin path; isolate board/log/state paths and the test tmux socket. Set Neovim's log path inside the fixture and bypass user config/shada.
- **Verify:** a passing case exits 0, an intentional assertion exits nonzero, unknown/empty selection fails, and cleanup touches only recorded fixture resources. Running it leaves the repository and user's board/tmux server unchanged.

#### [x] SDD-002 — Preserve the legacy observable contracts

- **Requires:** SDD-001. **Requirement:** R01, R18. **Scope:** `P/tests/legacy/`.
- **Deliver:** characterization fixtures for all public AISwarm commands/API forwards, API v2 snapshots, ID completion, root behavior, form preservation and ordered event deduplication. Record cancel/requeue and the audited regressions as current behavior, not desired v3 behavior.
- **Verify:** replay sequence 2→1→2 emits 1,2 once; prompt blank/header-like lines survive; reproductions show row-selection drift, stale retry report and absent automatic progress. Expected legacy quirks remain explicitly labelled and cannot satisfy v3 acceptance tests.

#### [x] SDD-003 — Add deterministic worker scenarios

- **Requires:** SDD-001. **Requirement:** R11, R18. **Scope:** `P/tests/fixtures/providers/`, scenario manifests.
- **Deliver:** a fake executable with controlled quiet, partial/UTF-8 output, interleaved streams, progress, failure, timeout, missing report, input request, flood and late-finish scenarios.
- **Verify:** each scenario produces its declared bytes/exit/timing signals under a test clock or synchronization barrier; no scenario resolves a real provider executable or contacts a network.

#### [x] SDD-004 — Prove the headless worker runtime is viable

- **Requires:** SDD-001, SDD-003. **Requirement:** R11, R18. **Scope:** disposable runtime prototype and a versioned decision record under `docs/aiswarm-decisions/`.
- **Deliver:** measure clean headless startup, async I/O, process-tree termination, ten-worker memory/CPU and record-to-reader latency on the supported runtime candidates. Record an explicit resource budget/decision; do not invent a passing threshold after seeing results.
- **Verify:** startup never loads a sentinel user config; a spawned grandchild is terminated in the cancellation experiment; records stream while the provider runs. Save measurements and accept/reject the runtime before dependent production work. Rejection requires a revised runtime contract and repeat experiment.

#### [x] SDD-005 — Specify control-journal transaction boundaries

- **Requires:** SDD-002. **Requirement:** R03. **Scope:** a durability decision record and failure-point fixture descriptions.
- **Deliver:** exact on-disk board/task/attempt layout, lock ownership/liveness check, write-ahead event and projection order, flush/rename boundaries, partial-record recovery and permitted rollback. Decide batch transaction framing before implementing add/edit.
- **Verify:** manually walk crash points before/after lock, append, flush, projection replacement and sidecar update. Every point has one deterministic recovery outcome, no reused committed sequence and no lost committed task. Distinguish process-crash tests from power-loss durability claims.

#### [x] SDD-006 — Freeze stream, cursor and acknowledgement contracts

- **Requires:** SDD-005. **Requirement:** R03, R12. **Scope:** protocol decision record and valid/invalid JSON fixtures.
- **Deliver:** control/telemetry/frame schemas; stable IDs; composite cursor encoding/version; checkpoint acquisition; pagination; filter advancement; stale/gap/generation behavior; durable consumer ack validation. Define ordering across stdout/stderr and sources without claiming global causality.
- **Verify:** contract walkthrough covers concurrent attach/appends, an unseen new attempt, filtered-out records, replay duplicates, cursor from another board, ack beyond delivered history and a consumer reconnect with different filters. Define rejection/resync outcomes and examples that round-trip.

#### [x] SDD-007 — Resolve UI boundary cases in a layout contract

- **Requires:** none. **Requirement:** R07, R16. **Scope:** layout/key-action decision record.
- **Deliver:** an exhaustive breakpoint table and focus/action contract. Resolve the spec's ≥110-column/24–27-row gap by using the two-pane layout without a tray; compute thresholds from interior size. Define narrow fallback, selection removal, pinned inspector behavior and cancellation prompt focus.
- **Verify:** every integer width/height region maps to one valid layout; walk keys through Tasks→Inspect→Back, composer Esc, cancel confirmation and view-follow pause. The clarification changes no core interaction or latency requirement.

#### [x] SDD-008 — Add task evidence and traceability validation

- **Requires:** SDD-001. **Requirement:** R17, R18. **Scope:** runner reports, ignored artifact directory, plan validation utility.
- **Deliver:** evidence records and checks for unique IDs, existing dependencies, acyclic ordering and requirement ownership; validate manual evidence explicitly instead of treating it as an automated test.
- **Verify:** duplicate task, missing dependency, cycle, absent evidence or nonexistent artifact is reported. Valid fixture evidence is accepted; generated runtime artifacts do not enter Git status.

### Compatibility: adopt the name without replacing board data

#### [x] SDD-009 — Establish the canonical Lua/plugin namespace

- **Requires:** SDD-002. **Requirement:** R01. **Scope:** plugin directory, `P/lua/aiswarm/`, lazy spec.
- **Deliver:** use the standalone canonical package and lazy `main="aiswarm"`; keep only internal schema-v2 storage adapters.
- **Verify:** loading the canonical module repeatedly produces one state instance, one follower and one command registration. No data directory is moved.

#### [x] SDD-010 — Provide canonical CLI launchers

- **Requires:** SDD-009. **Requirement:** R01. **Scope:** `P/bin/aiswarm`, `aiswarm-push`, `aiswarm-progress`.
- **Deliver:** canonical executable discovery and argument-preserving invocation in the standalone checkout.
- **Verify:** execute the canonical launcher on v2/v3 fixtures with spaced/quoted prompt paths; verify prompt bytes, exit status and stdout/stderr.

#### [x] SDD-011 — Normalize canonical configuration and environment

- **Requires:** SDD-009, SDD-010. **Requirement:** R01. **Scope:** config/environment resolution shared by launcher and client.
- **Deliver:** type/range validation and explicit option → AISWARM_ROOT → discovery precedence; only canonical environment names are read.
- **Verify:** table-driven unset/conflicting/invalid values yield the same effective root and defaults from CLI and Neovim; invalid settings fail before jobs/files are created. Unset provider defaults to the backend registry's eventual mock default.

#### [x] SDD-012 — Register the canonical command once

- **Requires:** SDD-009, SDD-011. **Requirement:** R01. **Scope:** `P/plugin/aiswarm.lua`, commands module.
- **Deliver:** canonical subcommand parser and completion, registered under one `:AISwarm` command. Route existing features; reject unimplemented v3-only actions with an explicit capability message until wired.
- **Verify:** repeated loading registers the command once; visual range reaches composition unchanged; unknown subcommands fail clearly; legacy optional-ID behavior remains covered until contextual resolution is installed in SDD-052.

#### [x] SDD-013 — Move user entry keys to the AI swarm group

- **Requires:** SDD-012. **Requirement:** R01, R17. **Scope:** local lazy spec and `lua/plugins/which-key.lua`.
- **Deliver:** `<leader>Aa/Ap/An/Al/Ar` with accurate descriptions and range handling; remove AISwarm's conflicting global H mappings; inspect existing runtime conflicts before installing defaults.
- **Verify:** inspect mappings in an ordinary buffer and a Git-tracked buffer. AISwarm no longer shadows/advertises H picker/results, Git H actions and Sidekick lowercase a actions remain intact, and visual An retains selected lines.

#### [x] SDD-014 — Route push through the canonical session

- **Requires:** SDD-009, SDD-011. **Requirement:** R01, R17. **Scope:** push helper, canonical RPC and registration cleanup.
- **Deliver:** the push entry point targets the canonical store with root checks; preserve owner-checked registration teardown and useful failed-registration diagnostics.
- **Verify:** duplicate delivery through stream and push emits one event; mismatched root is rejected; one editor's teardown cannot erase another's registration. Missing/dead registration never disables the follower.

#### [x] SDD-015 — Introduce explicit project session ownership

- **Requires:** SDD-009, SDD-011. **Requirement:** R02, R14. **Scope:** `project.lua`, session lifetime.
- **Deliver:** ancestor discovery, canonicalized roots, project switching independent of setup, and generation ownership of pending callbacks.
- **Verify:** nested cwd and symlink fixtures select the intended board; cwd change alone does not retarget actions; explicit switch keeps preferences and invalidates old callbacks. Only `.aiswarm` is auto-discovered; explicit paths preserve existing schema-v2 data.

#### [x] SDD-016 — Centralize provider discovery and defaults

- **Requires:** SDD-003, SDD-011. **Requirement:** R01, R15. **Scope:** `providers/registry.lua`, provider probe fixtures.
- **Deliver:** stable IDs, executable mappings including cursor→cursor-agent, version/capability probe interface and consistent mock fallback. Preserve existing argv construction until each adapter has verified alternatives.
- **Verify:** unavailable providers display unavailable, not silently selected; CLI/composer consume identical defaults; a generic one-shot provider advertises no input/tools/usage capabilities it cannot demonstrate.

### Lifecycle: make control operations trustworthy

#### [x] SDD-017 — Implement shared versioned validation

- **Requires:** SDD-005, SDD-006. **Requirement:** R03. **Scope:** `protocol.lua`, schema fixtures.
- **Deliver:** validators for board/task/attempt/control/telemetry records and mutation arguments, including IDs, bounded messages, payload ownership, types and schema versions.
- **Verify:** reject path traversal IDs, reserved envelope overrides, malformed numeric fields and unsupported major versions. Accept allowed additive fields and inspect unknown event types without changing lifecycle state.

#### [x] SDD-018 — Initialize an identified v3 board

- **Requires:** SDD-011, SDD-017. **Requirement:** R02, R03. **Scope:** init command and board manifest writer.
- **Deliver:** explicit initialization with persisted UUID/schema/generation and context templates; keep reads/opening side-effect free.
- **Verify:** initialization twice preserves identity/context; separate boards get different identities; commands against a missing board report missing without creating a `locks/` fragment.

#### [x] SDD-019 — Implement owned board mutation locks

- **Requires:** SDD-005, SDD-018. **Requirement:** R03. **Scope:** runtime lock helper.
- **Deliver:** bounded acquisition, owner process/start identity, normal cleanup and diagnosed recovery for proven-dead owners; migration/write mutual exclusion.
- **Verify:** concurrent contenders serialize; a live owner is never stolen; SIGKILL fixture leaves a recoverable lock; reused PID/unknown ownership does not trigger unsafe deletion. Timeout returns an actionable error.

#### [x] SDD-020 — Append committed control transactions

- **Requires:** SDD-017, SDD-019. **Requirement:** R03. **Scope:** control journal writer and fault injection.
- **Deliver:** allocate sequence from committed journal authority, validate then append/flush per SDD-005, and treat sequence sidecar as a hint.
- **Verify:** concurrent writers produce unique contiguous committed sequences. Inject failure before/after append/flush/sidecar; a missing sidecar or uncommitted trailing fragment cannot allocate a conflicting committed sequence.

#### [x] SDD-021 — Build task projections and consistent snapshots

- **Requires:** SDD-020. **Requirement:** R03. **Scope:** pure control reducer, projection publication, snapshot command.
- **Deliver:** deterministic reducers and atomic projection replacement; snapshots report only fully applied committed sequence and recompute validated counts.
- **Verify:** replaying the same committed transactions twice yields identical tasks/counts; snapshot concurrent with a multi-record mutation cannot expose half an operation or a sequence beyond its projections.

#### [x] SDD-022 — Recover control state after interrupted writes

- **Requires:** SDD-021. **Requirement:** R03. **Scope:** startup recovery/quarantine.
- **Deliver:** restore missing/stale projections, reconcile sidecar, quarantine incomplete tail and report corruption requiring intervention; finish recovery before serving mutations/snapshots.
- **Verify:** restart at every SDD-005 crash point and compare state to committed transactions. Valid committed history survives; corrupt interior records are not silently skipped; recovered event sequence does not stall on an invented hole.

#### [x] SDD-023 — Enqueue task and prompt as one operation

- **Requires:** SDD-016, SDD-022. **Requirement:** R03, R04. **Scope:** v3 add transaction.
- **Deliver:** backend ID allocation and atomic publication of validated task intent plus prompt; return structured ID/revision and retain explicit-ID support.
- **Verify:** simultaneous auto-ID adds are unique; duplicate explicit ID conflicts; a crash cannot leave a visible task without its prompt or an inaccessible committed prompt/task pair. Empty/invalid inputs leave the board unchanged.

#### [x] SDD-024 — Apply queued edits with revision checks

- **Requires:** SDD-023. **Requirement:** R03, R04. **Scope:** atomic set/edit transaction and prompt update.
- **Deliver:** one validator/transaction for metadata and prompt; require expected revision and queued state.
- **Verify:** invalid provider/timeout in a multi-field edit causes no partial writes; stale revision conflicts; dispatch racing edit admits one valid serialization and never edits an already-running attempt's immutable prompt.

#### [x] SDD-025 — Validate dependency graph and derive blockers

- **Requires:** SDD-024. **Requirement:** R04. **Scope:** dependency validator and eligibility projection.
- **Deliver:** enforce missing/self/cycle checks on creation/edit and compute unsatisfied dependency reasons without inventing execution failures.
- **Verify:** direct/indirect cycles and missing IDs are rejected. Failed/cancelled upstream blocks downstream with the exact ID/reason; retry alone does not unblock it, but upstream success does.

#### [x] SDD-026 — Reorder the numeric ready queue

- **Requires:** SDD-025. **Requirement:** R04. **Scope:** move/reorder transaction and comparator.
- **Deliver:** numeric order with defined ties and priority rebalance, preserving nonnegative validated priorities.
- **Verify:** move-first at priority 0 stays legal; large priorities sort numerically; repeated moves give the requested order; reorder racing dispatch cannot mutate a running task.

#### [x] SDD-027 — Create immutable execution attempt identities

- **Requires:** SDD-023. **Requirement:** R05. **Scope:** attempt reservation record/path helpers.
- **Deliver:** unique attempt IDs/ordinals, frozen execution config and separate prompt/log/report/telemetry paths; distinguish task ID from current attempt identity.
- **Verify:** two attempts of one task have disjoint artifact paths; task edits cannot rewrite a reserved attempt's config; imported/unknown historical identity remains explicitly distinguishable.

#### [x] SDD-028 — Scope tmux operations to board and attempt ownership

- **Requires:** SDD-004, SDD-027. **Requirement:** R05. **Scope:** tmux target helper and attach/peek/wait/gc/down commands.
- **Deliver:** stored session/pane identities plus full ownership options; validate ownership before lookup/mutation; retain inspectability of finished panes.
- **Verify:** two boards with T-001 coexist on one isolated tmux server. Each command affects only the expected board/attempt; forged or reused session name fails ownership checks; cleanup never scans and kills arbitrary `agent-*` sessions.

#### [x] SDD-029 — Persist and control one scheduler per board

- **Requires:** SDD-022, SDD-028. **Requirement:** R02, R05. **Scope:** scheduler ownership/status/start/stop/pause/resume.
- **Deliver:** singleton identity/heartbeat, authoritative WIP/effective settings and distinct pause versus stop behavior.
- **Verify:** concurrent starts create one scheduler; editor environment cannot change reported running WIP; pause stops new dispatch but leaves workers; stop reports monitoring stopped and does not kill workers.

#### [x] SDD-030 — Enforce requested worktree isolation

- **Requires:** SDD-023, SDD-028. **Requirement:** R05. **Scope:** enqueue preflight/worktree reservation and effective cwd.
- **Deliver:** provision or validate the requested isolated location before making the task runnable; reject failed isolation instead of falling back to shared cwd. Record ownership for cleanup of failed preparation.
- **Verify:** missing Git/config, invalid path and worktree creation failure leave no runnable task; explicit shared mode records its path; retry cannot accidentally reuse an unrelated board's worktree. Cleanup removes only resources created by that preparation.

#### [x] SDD-031 — Dispatch a reserved attempt atomically

- **Requires:** SDD-025, SDD-026, SDD-027, SDD-029, SDD-030. **Requirement:** R04, R05. **Scope:** dispatch transaction and spawn acknowledgement.
- **Deliver:** eligibility/WIP selection, attempt reservation, starting state and rollback/structured failure on spawn failure or startup deadline.
- **Verify:** concurrent dispatchers cannot exceed WIP or start the same task twice; blocked work is skipped; failed spawn releases capacity and records one accurate outcome instead of leaving a phantom active task.

#### [x] SDD-032 — Fence attempt start and finish transitions

- **Requires:** SDD-031. **Requirement:** R05. **Scope:** started/finished transactions.
- **Deliver:** current-attempt/revision checks, idempotent terminal outcomes and typed exit/reason/timing data.
- **Verify:** duplicate finish produces one outcome; a late finish from attempt 1 cannot alter attempt 2; nonzero exit and timeout preserve correct reason; terminal outcomes never move backward into running.

#### [x] SDD-033 — Cancel without automatic requeue

- **Requires:** SDD-028, SDD-032. **Requirement:** R05. **Scope:** cancel operation and process-tree grace/force stop.
- **Deliver:** cancel queued intent or the identified running attempt; terminate only its owned process tree and commit one cancelled outcome.
- **Verify:** run multiple scheduler ticks after cancellation: no rerun occurs. Graceful and unresponsive child/grandchild fixtures terminate as specified; cancel/finish race yields one terminal result; completed task is rejected as a stale target.

#### [x] SDD-034 — Retry into a fresh attempt

- **Requires:** SDD-033. **Requirement:** R05. **Scope:** explicit retry transaction.
- **Deliver:** retry eligible terminal tasks with a new attempt identity and clean outcome metadata while retaining previous evidence.
- **Verify:** retry returns work to the queue exactly once, keeps prior logs/report readable, and new execution cannot write to prior artifact paths. Running-task retry and duplicated stale request conflict safely.

#### [x] SDD-035 — Reconcile process health independently of sessions

- **Requires:** SDD-029, SDD-032. **Requirement:** R05. **Scope:** worker/pane reconciliation and health projection.
- **Deliver:** evaluate expected process/pane/start identity; distinguish quiet, stale/unknown telemetry and proven orphan death; retained sessions remain inspectable.
- **Verify:** a retained dead pane with no finish becomes orphaned after reconciliation; quiet live process stays running; missing heartbeat alone never becomes failure; scheduler stopped is not interpreted as all workers dead.

#### [x] SDD-036 — Associate report quality with the exact attempt

- **Requires:** SDD-027, SDD-032. **Requirement:** R05. **Scope:** report/artifact finalization.
- **Deliver:** resolve only that attempt's report; distinguish complete, incomplete, missing and synthesized; keep exit outcome, reported verification and known usage separate.
- **Verify:** a new successful attempt that writes no report cannot display its predecessor's report; missing usage remains null; a model's “tests passed” text is labelled reported, not independently verified.

#### [x] SDD-037 — Translate legacy mutations onto v3 semantics

- **Requires:** SDD-012, SDD-033, SDD-034, SDD-036. **Requirement:** R01. **Scope:** v3 compatibility write adapter.
- **Deliver:** translate established AISwarm operations through validated v3 transactions, preserving documented legacy kill→cancel-and-requeue as one serialized compatibility operation and warning explicitly.
- **Verify:** `AISwarmKill`/old CLI kill requeues exactly once on v3; canonical cancel does not. No compatibility path bypasses current-attempt, revision, dependency or path validation.

### Migration: make existing boards usable without losing evidence

#### [x] SDD-038 — Implement a read-only migration inventory

- **Requires:** SDD-002, SDD-015, SDD-017. **Requirement:** R06. **Scope:** migrate dry-run inventory.
- **Deliver:** inspect schema, task states, worker/scheduler/lock ownership, absolute paths, reports, missing evidence and identity conflicts.
- **Verify:** compare full file hashes/metadata before and after dry-run: unchanged. Incomplete/active/ambiguous fixtures produce explicit findings instead of invented attempt history.

#### [x] SDD-039 — Acquire migration quiescence and a verified backup

- **Requires:** SDD-019, SDD-029, SDD-038. **Requirement:** R06. **Scope:** migration lock/marker, backup manifest/checksums.
- **Deliver:** require stopped legacy writers/workers, block compliant writers during migration and back up original data before staging any conversion.
- **Verify:** live-writer fixture refuses migration; backup checksum verification detects corruption; backup failure leaves source unchanged; migration marker blocks competing mutations. Document that unknown old binaries cannot be made cooperative by this marker.

#### [x] SDD-040 — Convert v2 evidence into staged v3 records

- **Requires:** SDD-022, SDD-027, SDD-036, SDD-039. **Requirement:** R06. **Scope:** pure/import-staging converter.
- **Deliver:** board identity and validated task records, one labelled legacy attempt where execution evidence exists, and preserved/referenced raw artifacts and absolute paths.
- **Verify:** import ready/done/failed and reconciled-active fixtures; preserve report/log checksums; missing timestamps/history remain unknown; converter emits no runnable worker or scheduler side effect.

#### [x] SDD-041 — Publish, resume and roll back migration transactionally

- **Requires:** SDD-040. **Requirement:** R06. **Scope:** staged validation and final manifest commit marker.
- **Deliver:** validate referential integrity, publish schema marker last, and resume/restore interrupted migration using its manifest. Prevent destructive downgrade after new v3 work.
- **Verify:** interrupt at every publish boundary and resume/roll back; exactly one valid board schema becomes authoritative. Rollback before new work restores original checksums; rollback after new attempts refuses overwrite and explains export/reconciliation.

#### [x] SDD-042 — Expose migration state in project selection

- **Requires:** SDD-015, SDD-041. **Requirement:** R02, R06. **Scope:** project/migration command views.
- **Deliver:** show legacy capabilities, inventory/upgrade action and migrated-history labels; preserve the `.aiswarm` storage location unless a separate move is chosen.
- **Verify:** user can inspect a legacy board, see why a v3-only action is unavailable, review dry-run and migrate without automatic scheduler start. An interrupted upgrade displays recovery state rather than an empty queue.

#### [x] SDD-043 — Verify the compatibility and migration matrix

- **Requires:** SDD-013, SDD-014, SDD-016, SDD-037, SDD-042. **Requirement:** R01, R06, R18. **Scope:** acceptance cases/evidence only.
- **Deliver:** matrix for the single executable/module/command namespace, environment precedence, v2/v3 boards, explicit root selection, push and migration/rollback.
- **Verify:** run `--suite compatibility`; each supported combination passes and each unsupported combination fails explicitly. Confirm one runtime/store and no unintended move of board/worktree/branch data.

### Workspace: implement the user journeys against stable contracts

#### [x] SDD-044 — Create the asynchronous backend client

- **Requires:** SDD-011, SDD-015, SDD-017. **Requirement:** R07, R14. **Scope:** `backend.lua`.
- **Deliver:** argv-based typed commands, cancellation/timeouts, structured success/error callbacks and project-generation ownership; expose an injectable client for UI fixtures.
- **Verify:** delayed command never blocks a UI sentinel timer; timeout/start failure returns one callback; project switch suppresses an obsolete result; paths/prompts with shell metacharacters remain literal arguments.

#### [x] SDD-045 — Adapt legacy snapshots and events into the new client

- **Requires:** SDD-002, SDD-015, SDD-044. **Requirement:** R01, R07, R14. **Scope:** v2 read/transport adapter.
- **Deliver:** normalize legacy task/status data with explicit legacy capabilities while preserving serialized refresh, gap recovery and separate snapshot/delivery cursors.
- **Verify:** out-of-order and duplicate fixtures retain the characterized guarantees; initial historical events do not toast; missing v3 fields become unknown/unsupported rather than fabricated attempt history.

#### [x] SDD-046 — Implement the editor's normalized state store

- **Requires:** SDD-021, SDD-027, SDD-045. **Requirement:** R07. **Scope:** `store.lua`, pure reducer tests.
- **Deliver:** validated snapshots/control events, task/attempt lookup and cached selectors with subscription/error isolation. Support fixture telemetry shapes without starting production I/O.
- **Verify:** idempotent replay gives identical state; state transitions honor attempt identity; subscriber failure does not prevent other subscribers; selectors/counts perform no subprocess/file I/O.

#### [x] SDD-047 — Preserve view selection by identity

- **Requires:** SDD-046. **Requirement:** R07. **Scope:** view-state model for project/task/attempt/tab/filter/pin.
- **Deliver:** selection keyed by IDs, stable fallback when the selected task disappears and independent pinned inspector/feed selection.
- **Verify:** active→finished reorder retains the selected task and action target; filtering/removal picks the documented neighbor or empty state; a pinned inspector does not silently follow task cursor changes.

#### [x] SDD-048 — Batch visible rendering and bound pending work

- **Requires:** SDD-046. **Requirement:** R07, R13. **Scope:** UI render scheduler.
- **Deliver:** dirty-region scheduling, coalescing and bounded pending render work; do not request a snapshot or full redraw per output/heartbeat event.
- **Verify:** a burst of fixture events yields bounded scheduled batches with final correct state; hidden views schedule no rendering/animation; reconciliation is not proportional to raw output count.

#### [x] SDD-049 — Build the persistent workspace shell

- **Requires:** SDD-007, SDD-047, SDD-048. **Requirement:** R07. **Scope:** `ui/workspace.lua`, Snacks window ownership.
- **Deliver:** task/inspector/tray panes in one reusable floating workspace and optional docked editor layout; opening focuses the existing workspace; closing releases only view resources.
- **Verify:** repeated open produces one workspace; pane actions do not close it; q returns editor focus without stopping a fixture worker/scheduler; docked mode preserves normal editing windows.

#### [x] SDD-050 — Add theme-aware, display-cell-safe primitives

- **Requires:** SDD-049. **Requirement:** R16. **Scope:** highlights, text truncation/padding/extmark helpers.
- **Deliver:** specified semantic groups, textual states, ASCII/Unicode/custom icons and user-preserving ColorScheme defaults; sanitize control/OSC content in ordinary buffers.
- **Verify:** CJK, emoji and combining-mark fixtures align/truncate without broken extmarks; ASCII needs no Nerd Font; theme reload preserves explicit overrides; malicious control sequences appear as sanitized data and do not trigger terminal actions.

#### [x] SDD-051 — Render grouped task lists and filters

- **Requires:** SDD-047, SDD-048, SDD-050. **Requirement:** R07. **Scope:** `ui/tasks.lua`.
- **Deliver:** Running/Attention/Queued/Finished sections, collapsible groups, stable running order, numeric queue order, newest-first finished order and explicit dependency reasons.
- **Verify:** a mixed 1,000-task fixture yields correct counts/order/filter membership; collapsing or live status changes preserves valid selected ID; failure/blocking states carry readable text, not only color.

#### [x] SDD-052 — Resolve and execute contextual actions safely

- **Requires:** SDD-033, SDD-034, SDD-037, SDD-044, SDD-051. **Requirement:** R08. **Scope:** action registry, command routing and help menu.
- **Deliver:** resolve omitted ID from current context or task picker; capture board/task/attempt/revision; show legal actions; separate canonical cancel and retry; bind workspace keys and contextual hints.
- **Verify:** a state change while an action menu/confirmation is open returns conflict instead of hitting another task. Cancel confirmation names the attempt; a taskless row cannot close the board or execute an action; Enter inspects and g attaches explicitly.

#### [x] SDD-053 — Apply responsive layout and preserve navigation

- **Requires:** SDD-007, SDD-049, SDD-050. **Requirement:** R07, R16. **Scope:** resize/layout resolver.
- **Deliver:** exhaustive wide/medium/narrow/minimal layouts from SDD-007, interior-dimension measurement and documented keyboard pane navigation.
- **Verify:** resize through 140×45, 100×30, 80×24, 60×20 and 35×10 plus exact breakpoint boundaries; no invalid dimensions, disappearing selected identity, stolen focus or lost log scroll/tab/filter.

#### [x] SDD-054 — Implement cancellable inspector reads

- **Requires:** SDD-044, SDD-047. **Requirement:** R08. **Scope:** `ui/inspector.lua`, bounded async preview/file loader.
- **Deliver:** selection/generation tokens, read cancellation and explicit loading/empty/read-failed states; cache bounded content by attempt/artifact identity.
- **Verify:** select A then B while A's delayed read finishes last: only B renders. A large/slow artifact cannot freeze a UI sentinel; stale errors do not overwrite B; zero output differs from a failed read.

#### [x] SDD-055 — Render an honest attempt overview

- **Requires:** SDD-016, SDD-035, SDD-036, SDD-054. **Requirement:** R05, R08, R10. **Scope:** overview view and field selectors.
- **Deliver:** provider/attempt/effective cwd/dependencies/timing, separate heartbeat/output/activity ages, execution outcome, report quality, verification provenance and nullable cost.
- **Verify:** quiet/stale/orphan/missing-report/unknown-cost fixtures display distinct correct labels. A reported testing phase requires provenance; no fixture invents progress percentage, hidden reasoning or independently verified tests.

#### [x] SDD-056 — Implement bounded output inspection

- **Requires:** SDD-006, SDD-054. **Requirement:** R08, R10, R13. **Scope:** `ui/output.lua`, fixture stream interface.
- **Deliver:** stdout/stderr distinction, follow/search/wrap, explicit full-transcript action, 10,000-line/2 MiB view limits and attempt-pinned output selection.
- **Verify:** flood fixture stays within both limits; scrolling/search suspends autoscroll and increments unread count; f/G resume as documented; changing attempts cannot mix bytes; full-transcript action selects the correct artifact.

#### [x] SDD-057 — Render the selected attempt's report

- **Requires:** SDD-036, SDD-054. **Requirement:** R08. **Scope:** report tab and results picker source.
- **Deliver:** Markdown preview and missing/incomplete/synthesized labels, with explicit task/attempt identity in search results.
- **Verify:** retry with no new report shows missing rather than predecessor text; selecting a historical attempt intentionally opens its own report; async read errors preserve workspace/task selection.

#### [x] SDD-058 — Expose reported file artifacts with provenance

- **Requires:** SDD-057. **Requirement:** R08. **Scope:** Files tab and optional diff action.
- **Deliver:** derive paths from structured artifacts/report sections, label provenance, resolve relative paths against recorded cwd and gate optional diff integrations.
- **Verify:** fixture file opens the intended worktree path; shared-directory changes are not labelled exclusively owned by one task; missing file/diff dependency yields a recovery message, not a crash or silent substitution.

#### [x] SDD-059 — Navigate immutable attempt history

- **Requires:** SDD-027, SDD-036, SDD-054. **Requirement:** R05, R08. **Scope:** Attempts tab and cross-tab attempt selection.
- **Deliver:** per-attempt ordinal, provider, start/end/reason and links into its Activity/Output/Report views, including explicit imported-legacy labels.
- **Verify:** switching among successful, failed, cancelled and imported attempts changes every artifact view consistently; a new attempt arriving does not overwrite a pinned historical selection.

#### [x] SDD-060 — Keep the task picker live without losing its query

- **Requires:** SDD-051, SDD-052, SDD-054. **Requirement:** R07, R08. **Scope:** Snacks task picker source/actions.
- **Deliver:** subscribe to task updates while open, preserve search/selected ID and use cancellable previews; Enter opens the inspector.
- **Verify:** a selected task changes state during a query: row/preview refresh without query loss or retargeting; closing picker unsubscribes; action on a stale record is rejected by the shared action layer.

#### [x] SDD-061 — Build the prompt-first composer

- **Requires:** SDD-016, SDD-044. **Requirement:** R09. **Scope:** `ui/composer.lua`, basic fields.
- **Deliver:** prompt buffer with Title/Provider/Isolation header, provider picker/availability and optional source-range context; advanced fields initially collapsed.
- **Verify:** keyboard-only composition starts in useful prompt context, provider default matches CLI, unavailable provider cannot be silently submitted, and source selection/blank lines remain intact.

#### [x] SDD-062 — Add validated advanced task settings

- **Requires:** SDD-025, SDD-030, SDD-061. **Requirement:** R04, R09. **Scope:** dependency multi-picker and priority/timeout/isolation controls.
- **Deliver:** shared schema-backed advanced fields with backend-authoritative validation and displayed effective working directory.
- **Verify:** missing/self/cyclic dependencies and invalid numeric values identify their fields; worktree failure never falls back to shared mode; choosing shared mode is explicit and shows the actual path.

#### [x] SDD-063 — Persist and restore project-scoped drafts

- **Requires:** SDD-015, SDD-061. **Requirement:** R09. **Scope:** draft storage/debounce/restore.
- **Deliver:** autosaved prompt/metadata/source context keyed to project; Esc preserves draft; discard is explicit and scoped.
- **Verify:** close/reopen and simulated editor restart restore latest flushed draft; project switch cannot submit a draft to another board; concurrent drafts do not overwrite each other; discard removes only the chosen draft.

#### [x] SDD-064 — Submit and edit tasks without losing input

- **Requires:** SDD-023, SDD-024, SDD-062, SDD-063. **Requirement:** R09. **Scope:** composer write actions and advanced `#:` import/export.
- **Deliver:** Ctrl-s/:w validated add/edit, backend auto-ID default, duplicate-submission guard, inline errors and old-form import/export through the same validator.
- **Verify:** duplicate save creates one task; backend conflict retains draft and focuses error; successful edit carries expected revision; imported prompt survives round-trip including blank/header-like lines. Successful submission selects the queued task.

#### [x] SDD-065 — Complete the first-use and recovery journey

- **Requires:** SDD-015, SDD-018, SDD-029, SDD-064. **Requirement:** R02, R09. **Scope:** no-board/empty/stopped/offline workspace states.
- **Deliver:** explicit create/open board and scheduler start actions, cached-offline display, reconnect affordance and project switch prompt/action without automatic retargeting.
- **Verify:** from no board, keyboard-only user creates a board, chooses mock, queues a task and starts scheduler. Opening alone creates nothing; queueing on a stopped scheduler explains why work waits; disconnect retains cached data and draft with age.

#### [x] SDD-066 — Implement the combined activity view

- **Requires:** SDD-006, SDD-048, SDD-050. **Requirement:** R10, R13. **Scope:** `ui/activity.lua`, fixture event source.
- **Deliver:** typed/provenanced feed, filters for task/provider/attempt/kind/severity/text, pinned scope, follow/unread behavior and bounded history (2,000 records/4 MiB global; 500 per selected attempt).
- **Verify:** mixed-source fixtures sort deterministically without changing control order; heartbeat/raw-output entries are hidden by default but queryable; selected text/search does not jump; every bound holds under flood; repeated previews coalesce with an honest count.

#### [x] SDD-067 — Deduplicate actionable notifications

- **Requires:** SDD-046, SDD-066. **Requirement:** R10. **Scope:** notification policy and local owner selection.
- **Deliver:** failure/completion/supported-input policy, burst aggregation, persistent attention acknowledgement and one owner across editor/desktop/tmux channels.
- **Verify:** duplicate push/stream completion produces at most one configured notification; reconnect history produces none; raw output/progress flood produces no toast storm; failed/orphaned reason mapping is consistent.

#### [x] SDD-068 — Verify complete fixture-backed keyboard journeys

- **Requires:** SDD-013, SDD-052, SDD-053, SDD-055, SDD-056, SDD-057, SDD-058, SDD-059, SDD-060, SDD-064, SDD-065, SDD-066, SDD-067. **Requirement:** R07, R08, R18. **Scope:** integration evidence only.
- **Deliver:** deterministic scripts for new→queue→inspect→cancel→retry→report and blocked-task recovery using fixture-backed state where production telemetry is unavailable.
- **Verify:** activity/output/report are reachable within two actions from a selected task; workspace/selection persist; Ctrl-w/Tab/Esc semantics match the contract. Label these results fixture-backed and leave live reporting acceptance pending.

### Live telemetry: connect workers, editor and orchestrator

#### [x] SDD-069 — Package the clean production worker bootstrap

- **Requires:** SDD-004, SDD-016, SDD-028. **Requirement:** R11. **Scope:** `P/runtime/worker.lua`, bundled runtime loader.
- **Deliver:** resolve headless Neovim absolutely, load only bundled modules and run the selected provider argv in the owned attempt environment/cwd; connect dispatch to this bootstrap when capabilities are enabled.
- **Verify:** poisoned user init/plugin/shada fixtures are never read/executed; worker starts via tmux and independently of an open editor; paths with spaces work; missing Neovim returns an environment error before a phantom running task is recorded.

#### [x] SDD-070 — Capture and batch raw stdout/stderr

- **Requires:** SDD-069. **Requirement:** R11, R13. **Scope:** async worker I/O and raw-log segment writer.
- **Deliver:** separate byte streams, bounded write queue, flushed offset ranges and batch threshold of 100 ms or 16 KiB; no subprocess per line.
- **Verify:** reconstruct both original byte streams from split/multiline/interleaved fixtures; offsets reference flushed bytes exactly; output arrives before provider exit; large output does not block process supervision or grow queues without bound.

#### [x] SDD-071 — Connect provider exit and timeout to attempt outcome

- **Requires:** SDD-032, SDD-033, SDD-069. **Requirement:** R05, R11. **Scope:** worker completion/timeout/cancellation handling.
- **Deliver:** correct provider exit propagation, configurable task deadline and graceful/forced process-tree termination through existing lifecycle operations.
- **Verify:** success/nonzero/timeout/cancel/grandchild fixtures each produce one accurate terminal outcome; collector failure is not misreported as the provider exit code; a late callback cannot revive or overwrite a cancelled attempt.

#### [x] SDD-072 — Emit independent worker heartbeats

- **Requires:** SDD-035, SDD-069. **Requirement:** R11. **Scope:** worker watchdog source.
- **Deliver:** every-5-second process observations independently of output, updating heartbeat health separately from last output/progress.
- **Verify:** quiet process still emits heartbeats; after three missed intervals state becomes telemetry stale/unknown, not automatically failed; stopped worker emits no future heartbeats; scheduler reconciliation can establish actual death.

#### [x] SDD-073 — Persist one telemetry journal per attempt

- **Requires:** SDD-006, SDD-017, SDD-069. **Requirement:** R11, R13. **Scope:** attempt telemetry writer.
- **Deliver:** one owned writer, stable stream generation, monotonic attempt sequence, bounded append queue and no control-lock dependency for ordinary telemetry.
- **Verify:** concurrent telemetry from ten attempts stays correctly attributed and ordered per source; writer ownership rejects a second appender; restart does not reuse an event ID; control mutation remains responsive under telemetry flood.

#### [x] SDD-074 — Normalize raw/provider records without losing output

- **Requires:** SDD-016, SDD-070, SDD-073. **Requirement:** R11, R13, R15. **Scope:** generic adapter parsers and normalization layer.
- **Deliver:** incremental UTF-8/line parsing, output-range records with small sanitized preview, provenance and ≤64 KiB normalized records; unsupported native formats fall back to raw output.
- **Verify:** split JSON/UTF-8, unknown/malformed provider record and oversized line preserve raw bytes and yield bounded diagnostics. Unknown output never becomes fabricated phase/input/usage; parser failure does not change execution success.

#### [x] SDD-075 — Accept explicit worker updates through an inbox

- **Requires:** SDD-017, SDD-073. **Requirement:** R11. **Scope:** progress/report-event CLI and atomic spool consumption.
- **Deliver:** validated board/task/attempt-scoped inbox messages, consumed by the one telemetry writer; correlate retries of an accepted inbox message to prevent duplicate normalized updates.
- **Verify:** concurrent emitters preserve accepted messages and single-writer sequence; partial spool files are ignored/recovered; stale/mismatched attempt and reserved-key override are rejected; crash after append/before spool cleanup does not duplicate the event.

#### [x] SDD-076 — Expose telemetry/report instructions in worker context

- **Requires:** SDD-030, SDD-036, SDD-075. **Requirement:** R11. **Scope:** rendered prompt/context pack and worker environment.
- **Deliver:** absolute progress helper, board/task/attempt identity and exact attempt report path; retain mission/interfaces/decisions/dependency results and provenance rules.
- **Verify:** rendered prompt points into the current attempt and includes the intended dependency reports; stub worker can call helper from its worktree. Worker cooperation improves progress, but generic heartbeat/output still works when it ignores these instructions.

#### [x] SDD-077 — Restore latest activity from persisted telemetry

- **Requires:** SDD-072, SDD-073, SDD-074, SDD-075. **Requirement:** R11. **Scope:** per-attempt activity projection/recovery.
- **Deliver:** latest explicit phase/message/provenance and independent heartbeat/output/activity checkpoints; atomically publish after append and rebuild if stale.
- **Verify:** crash between append and projection replacement recovers the same latest activity; a fresh editor sees prior progress text with its actual age; heartbeat does not overwrite meaningful progress; old attempt cannot update the current projection.

#### [x] SDD-078 — Implement bounded stream frame encoding/decoding

- **Requires:** SDD-006. **Requirement:** R12, R13. **Scope:** shared frame codec and error frames.
- **Deliver:** JSONL framing with additive-field tolerance, schema checks and 256 KiB partial-frame limit; malformed/oversized frames have a declared diagnostic/resync outcome.
- **Verify:** every split boundary of representative frames round-trips; malformed UTF-8/JSON and missing newline cannot cause unbounded accumulation; unsupported major schema enters incompatible state and never mutates tasks.

#### [x] SDD-079 — Read raw logs incrementally by segment/offset

- **Requires:** SDD-070, SDD-078. **Requirement:** R12, R13. **Scope:** `logs` command/read helper.
- **Deliver:** bounded paged reads/follow with exact attempt, stream and segment identity; support ordinal lookup only after resolving it to immutable attempt ID.
- **Verify:** offset resumes return the expected bytes; stdout/stderr stay distinct; absent output differs from I/O error; a truncation/replaced segment cannot silently repeat or omit bytes.

#### [x] SDD-080 — Multiplex committed control and telemetry sources

- **Requires:** SDD-022, SDD-073, SDD-077, SDD-078, SDD-079. **Requirement:** R12. **Scope:** `P/runtime/stream.lua`, source discovery/watch loop.
- **Deliver:** one long-lived stream reader, incremental source offsets, new-attempt discovery, deterministic merge and filesystem-watch plus ≤250 ms polling fallback.
- **Verify:** appends and a new attempt become visible while reader stays alive; disabling watch notifications still delivers through fallback; control source order is preserved; no per-line jq/RPC process spawning occurs.

#### [x] SDD-081 — Bootstrap a stream without an attachment gap

- **Requires:** SDD-021, SDD-080. **Requirement:** R12. **Scope:** snapshot/checkpoint handshake.
- **Deliver:** connection capabilities and snapshot with control plus per-attempt checkpoints, followed by all subsequent events; recent-history request supports 200 context records without historical side effects.
- **Verify:** append/start/finish at each checkpoint acquisition boundary. Reconstructed consumer state matches committed state; an attempt created during attach is included or replayed, never lost; initial snapshot does not advance unrelated delivered cursors.

#### [x] SDD-082 — Resume and filter streams with composite cursors

- **Requires:** SDD-006, SDD-081. **Requirement:** R12. **Scope:** opaque cursor encoding, replay/pagination/filter semantics.
- **Deliver:** validated resumable source positions, explicit per-filter advancement and fully emitted-frame cursor updates; generation/board mismatch returns resync-required as specified.
- **Verify:** stop mid-frame, resume after a filtered page, append after completion and change filters according to contract. All retained eligible events are delivered at least once, duplicates retain IDs, and impossible/future/wrong-board cursors cannot skip accepted history silently.

#### [x] SDD-083 — Persist independent consumer acknowledgements

- **Requires:** SDD-082. **Requirement:** R12. **Scope:** `ack` command and consumer bookmark store.
- **Deliver:** validated board-scoped consumer names and atomic monotonic bookmarks, bounded by the cursor/ack contract; reconnect uses that consumer's accepted checkpoint.
- **Verify:** two consumers advance independently; crash before/after bookmark replacement yields a valid old/new bookmark; stale ack cannot regress it; malformed, unrelated-board and unissued/future cursor are rejected. Mere stream connection does not acknowledge delivery; the consumer, not the backend, is responsible for acknowledging only after downstream acceptance.

#### [x] SDD-084 — Rotate attempt history and signal explicit gaps

- **Requires:** SDD-070, SDD-073, SDD-082. **Requirement:** R13. **Scope:** segment rotation, retention and expired-cursor handling.
- **Deliver:** defaults of combined 100 MiB raw logs and 50 MiB telemetry per attempt, 7-day inactive history, immutable segment identities and retention-aware cursors; keep reports/control outcomes until explicit archive.
- **Verify:** small-cap fixtures exercise rotation/eviction without deleting an open segment; current writers continue; old cursor receives a specific gap/resync range; retained records remain replayable; default control/report evidence is not pruned.

#### [x] SDD-085 — Degrade predictably under slow/full storage

- **Requires:** SDD-070, SDD-073, SDD-084. **Requirement:** R13. **Scope:** worker/stream backpressure and storage-failure reporting.
- **Deliver:** bounded queues, coalesced optional previews, continued pipe draining, discarded-byte accounting and recovery gaps; lifecycle commit failure reports recovery-required instead of durable success.
- **Verify:** inject slow writes and ENOSPC: provider supervision remains responsive, memory stays within configured bounds, discarded bytes are counted, and storage recovery persists a gap. No successful durable lifecycle claim is made when its commit fails.

#### [x] SDD-086 — Demonstrate durable delivery to an external process

- **Requires:** SDD-083. **Requirement:** R12. **Scope:** subprocess orchestrator fixture and durable inbox example.
- **Deliver:** consumer that reads actual `stream`, deduplicates event IDs, persists accepted batches and acknowledges only afterward.
- **Verify:** kill/restart before durable accept, after accept/before ack and after ack. Every retained event is eventually accepted; duplicates have one inbox effect; two consumer instances do not corrupt bookmarks. Record this as subprocess delivery, not proof of an unspecified model API.

#### [x] SDD-087 — Produce bounded orchestrator briefings and export

- **Requires:** SDD-086. **Requirement:** R12. **Scope:** briefing reducer and explicit copy/export interface.
- **Deliver:** bounded task/attempt summaries with failure/blocker/progress prioritization and event references; preserve the subscription/raw evidence route when no runtime input API exists.
- **Verify:** fixture briefing includes a failure, its blocked dependents and latest progress without duplicate noise or invented state; truncation is labelled and links remain resolvable. Export alone never implies delivery to an AI conversation or acknowledges an unaccepted batch.

#### [x] SDD-088 — Implement the editor's v3 stream transport

- **Requires:** SDD-015, SDD-045, SDD-082. **Requirement:** R12, R14. **Scope:** `transport.lua`, canonical event API/autocmds.
- **Deliver:** stream process/framing/cursor ownership, schema negotiation, deduplication, subscriber delivery and selection of the v2 fallback by capability.
- **Verify:** duplicates yield one store side effect/notification; switching projects invalidates old frames; malformed frames cannot corrupt state; mixed versions choose declared modes. Canonical event subscribers receive the normalized envelope.

#### [x] SDD-089 — Connect production telemetry to inspector and activity

- **Requires:** SDD-055, SDD-056, SDD-066, SDD-077, SDD-088. **Requirement:** R10, R11. **Scope:** live store/activity/output bindings.
- **Deliver:** replace fixture sources with production projections/stream/log readers, retaining view bounds/pinning and separating heartbeat/output/progress ages.
- **Verify:** running mock worker updates visible progress text and output before completion; fresh attach restores previous activity; scrolling remains pinned; old attempts stay distinct. No raw record triggers synchronous preview or snapshot-per-line behavior.

#### [x] SDD-090 — Restrict compatibility push to low-volume control

- **Requires:** SDD-014, SDD-088. **Requirement:** R01, R12. **Scope:** push/event compatibility bridge.
- **Deliver:** canonical high-volume stream as the primary path; optional legacy `AISwarmEvent` translation off by default; use shared identity for control deduplication.
- **Verify:** same control record via follower/push reaches canonical subscribers once; optional legacy event is delivered only when enabled; raw output does not launch a push subprocess; registration failure leaves live streaming operational.

#### [x] SDD-091 — Reconnect and resynchronize with visible status

- **Requires:** SDD-084, SDD-085, SDD-088. **Requirement:** R12, R14. **Scope:** transport backoff, connection state and reconciliation.
- **Deliver:** jittered 250 ms→5 s backoff, explicit reconnect/offline/incompatible states, last-success age, gap resync and 10-second fallback reconciliation independent of output volume.
- **Verify:** dropped final completion is recovered; journal generation change/retention gap shows explicit resync; reconnect history causes no old toasts; repeated failure schedules one retry timer and success resets backoff after the defined healthy interval.

#### [x] SDD-092 — Verify lifecycle resource ownership and teardown

- **Requires:** SDD-068, SDD-069, SDD-091. **Requirement:** R14. **Scope:** leak/cleanup fixtures and any narrowly scoped lifecycle fixes.
- **Deliver:** ownership assertions for views, previews, stream jobs, runtime watchers, subscriptions, timers and server registration.
- **Verify:** repeated open/close/setup/project switches and exit return obsolete handle/job counts to baseline; late callbacks cannot render into wiped buffers; closing the workspace never kills workers; editor exit releases only its own registrations/consumers.

#### [x] SDD-093 — Verify the complete mock telemetry pipeline

- **Requires:** SDD-071, SDD-076, SDD-086, SDD-089, SDD-090, SDD-092. **Requirement:** R11, R12, R18. **Scope:** deterministic end-to-end evidence only.
- **Deliver:** worker→raw/telemetry/control journal→stream→editor and subprocess consumer scenarios using the actual bootstrap and dedicated tmux server.
- **Verify:** quiet/progress/partial output/failure/timeout/missing report/late finish scenarios satisfy all state and delivery assertions. Restore after editor and consumer restarts. No paid provider or fixture-only store shortcut may stand in for this gate.

### Core release: collect evidence for the advertised behavior

#### [x] SDD-094 — Make health diagnostics reflect actual capabilities

- **Requires:** SDD-004, SDD-016, SDD-035, SDD-043, SDD-091. **Requirement:** R15, R17. **Scope:** CLI doctor and Neovim health.
- **Deliver:** consistent version/runtime/dependency checks, provider capability diagnostics, actual scheduler state, root/schema/migration status, stream health and actionable recovery. Do not require unused flock or omit the selected timeout/runtime mechanism.
- **Verify:** missing dependency, unsupported version, legacy board, stopped scheduler, dead registration and degraded telemetry fixtures produce accurate severity/action in both surfaces. Neovim runtime requirement for standalone v3 worker/stream is explicit.

#### [x] SDD-095 — Integrate a cached aiswarm statusline

- **Requires:** SDD-046, SDD-094. **Requirement:** R17. **Scope:** public `statusline()` and `lua/plugins/lualine-nvim.lua`.
- **Deliver:** cached counts, attention/paused/connectivity indicator and optional click/open behavior supported by the chosen integration; avoid triggering plugin load while absent.
- **Verify:** repeated redraw calls perform no subprocess/file I/O; empty/unloaded state is unobtrusive; running/attention/offline fixture changes appear after store updates and never display stale counts as live.

#### [x] SDD-096 — Publish accurate package and migration documentation

- **Requires:** SDD-043, SDD-094, SDD-095. **Requirement:** R01, R17. **Scope:** root/plugin README, help files/tags, notices and runtime ignores.
- **Deliver:** canonical setup/keys, compatible old entry points, mock quickstart, migration/recovery instructions, truthful capability limits, standalone runtime prerequisites and actual license/third-party files backed by authoritative notices.
- **Verify:** resolve local links/help tags and manually run the documented mock quickstart in a disposable project; examples resolve the renamed binary. Old kill semantics and phase-5 optional capabilities are unmistakable. No missing license is filled with an invented assertion; unresolved provenance is recorded as a packaging blocker.

#### [x] SDD-097 — Measure the specified performance envelope

- **Requires:** SDD-004, SDD-068, SDD-093. **Requirement:** R18. **Scope:** benchmark runner and measurement artifact only.
- **Deliver:** exact 10-minute local-filesystem workload: 10 workers, 1,000 tasks, 200 normalized activity records/s aggregate, 1 MiB/s aggregate raw output. Instrument monotonic local flush/receipt/visible-render timestamps separately from provider buffering.
- **Verify:** p95 flushed record→visible display ≤500 ms and →external consumer receipt ≤500 ms; cached open p95 ≤100 ms; UI batch p95 ≤16 ms; documented UI bounds and predeclared worker-resource budget hold. Record sample count, percentile method, workload achieved, CPU/memory and dropped/coalesced/gap counts; include hidden/selected-output views. Slower-than-target run fails rather than lowering targets afterward.

#### [x] SDD-098 — Validate actual terminal usability and appearance

- **Requires:** SDD-053, SDD-068, SDD-089, SDD-095. **Requirement:** R16, R18. **Scope:** terminal screenshot/manual evidence only.
- **Deliver:** repeatable real-Neovim scripts/screenshots at 140×45, 100×30, 80×24, 60×20, 35×10; light/dark/ASCII/Unicode and motion disabled; exact breakpoint-edge checks.
- **Verify:** no clipping of essential actions/state, illegal geometry, unreadable selected row, broken wide glyph or focus/scroll jump. A first-time reviewer completes mock onboarding and can inspect output/report/activity in ≤2 actions from selected task. Record actual keystrokes/issues; headless buffer snapshots alone do not satisfy this task.

#### [ ] SDD-099 — Execute the platform and failure acceptance matrix

- **Requires:** SDD-022, SDD-031, SDD-035, SDD-041, SDD-086, SDD-092, SDD-096, SDD-097, SDD-098. **Requirement:** R18. **Scope:** core/compatibility/reliability/performance suite evidence only.
- **Deliver:** macOS Bash 3.2 with required tools and Linux runs; documented minimum Neovim 0.10.4 and the selected current stable runtime; pinned Snacks plus any explicitly supported new revision. Record exact versions/hardware, not moving “latest” labels in results.
- **Verify:** all automated suites and manual requirements pass on the supported combinations, including crash injection, retained dead pane, two boards, migration interruption, restart/ack boundaries, ENOSPC, rotation and full benchmark. Missing environment leaves that matrix cell unverified and the release gate pending.

#### [ ] SDD-100 — Close core implementation against the specification

- **Requires:** all SDD-001–099. **Requirement:** R18. **Scope:** core release checklist/evidence index only.
- **Deliver:** reconcile each requirement, audit finding and task with evidence; record supported versions and remaining optional capabilities. Remove or hide incomplete advertised core paths.
- **Verify:** every core checkbox has a passing evidence record and no unresolved P0/core defect remains. Demonstrate canonical rename + full keyboard journey + actual live logs/progress + external consumer recovery from one disposable board. Release status cannot be complete merely because the UI or rename shipped; no publishing/commit action is implied by this planning document.

### Optional integrations: enable capabilities only when verified

These tasks are independently optional. Unavailable credentials/provider versions are a recorded limitation for that integration, not a reason to mark its tests passed. Every adapter can retain the generic raw-output fallback delivered by core. Native capabilities require current official CLI documentation or supported introspection, versioned fixtures and explicit manual smoke evidence; never guess flags from another provider.

#### [ ] SDD-101 — Add a versioned Claude native-event adapter

- **Requires:** SDD-016, SDD-074, SDD-093. **Requirement:** R15. **Scope:** `providers/claude.lua`, recorded fixtures.
- **Deliver:** one verified CLI-version contract for public progress/tool/usage events and safe fallback when unsupported; document exact tested version and command construction.
- **Verify:** split/unknown/malformed event fixtures normalize correctly; missing usage stays null; native parser failure preserves raw logs. Explicitly authorized real-provider smoke confirms advertised fields without adding hidden-reasoning inference.

#### [ ] SDD-102 — Add a versioned Codex native-event adapter

- **Requires:** SDD-016, SDD-074, SDD-093. **Requirement:** R15. **Scope:** `providers/codex.lua`, recorded fixtures.
- **Deliver:** verified public event/exit/usage mapping for the tested CLI version, capability probe and generic fallback; retain explicit execution options.
- **Verify:** tool correlation/progress/terminal fixtures round-trip incrementally; unsupported version disables native claims; authorized smoke matches actual CLI fields. No report or usage values are inferred from plain text when absent.

#### [ ] SDD-103 — Add a versioned Gemini native-event adapter

- **Requires:** SDD-016, SDD-074, SDD-093. **Requirement:** R15. **Scope:** `providers/gemini.lua`, recorded fixtures.
- **Deliver:** verified native public event mapping where supported by the selected installed version; otherwise record raw-only capability explicitly.
- **Verify:** fixtures and authorized smoke prove each enabled native field; unsupported format falls back without changing execution outcome. Raw-only evidence cannot complete a claim of native streaming support.

#### [ ] SDD-104 — Add a versioned Aider activity adapter

- **Requires:** SDD-016, SDD-074, SDD-093. **Requirement:** R15. **Scope:** `providers/aider.lua`, recorded fixtures.
- **Deliver:** tested public output/activity capabilities for one supported version, with no artificial phase/usage values when no structured API exists.
- **Verify:** actual documented format is represented by deterministic fixtures and authorized smoke; probe matches behavior; unknown output remains raw and one-shot mode advertises no unsupported input response channel.

#### [ ] SDD-105 — Add a versioned Cursor native-event adapter (dropped: Cursor is not a target provider, owner decision 2026-09-14)

- **Status:** dropped. The owner does not use Cursor; no adapter, fixtures or smoke run will be produced and this task stays unchecked. The registry's generic raw-output path is unaffected.

- **Requires:** SDD-016, SDD-074, SDD-093. **Requirement:** R15. **Scope:** `providers/cursor.lua`, recorded fixtures.
- **Deliver:** tested cursor→cursor-agent mapping and public native events only for confirmed CLI capability/version; preserve raw fallback.
- **Verify:** executable/version mismatch is visible; split/invalid event fixtures retain raw output; authorized smoke matches enabled capabilities. No terminal paste is advertised as a supported model-message API.

#### [ ] SDD-106 — Deliver briefings into a named orchestrator runtime

- **Requires:** SDD-086, SDD-087. **Requirement:** R12, R15. **Scope:** one selected runtime's adapter and delivery fixtures.
- **Deliver:** record the exact target runtime/version/documented input API and accepted-message boundary, then implement durable handoff, deduplication and ack-after-acceptance. Instantiate this card separately for each additional runtime.
- **Verify:** fake input-API failures/restarts do not advance ack before durable acceptance; use/test documented runtime idempotency when available, otherwise disclose and test at-least-once handoff with possible duplicate messages. Authorized real integration proves runtime receipt. If no input API exists, leave integration unsupported and retain copy/export; do not mark generic subprocess receipt as model delivery.

#### [ ] SDD-107 — Add a capability-gated interactive input action

- **Requires:** SDD-052, SDD-067, SDD-074 and one completed SDD-101–104 adapter with a demonstrated bidirectional input capability. **Requirement:** R15. **Scope:** one provider's request/response channel and UI action.
- **Deliver:** request ID, valid response actions, user response routing and stale-request handling; show Waiting for input only from explicit provider requests.
- **Verify:** real protocol fixture accepts a response once for the correct current attempt/request; expired/duplicate response is rejected; one-shot/raw-only providers never expose this action. Input-required badge clears on provider acknowledgement, not on a successful terminal paste.

## 5. Audit finding closure map

Use the original audit for evidence and severity. Closing a finding requires its owning task's behavior/evidence, not simply mentioning it in documentation.

| Audit finding | Owning task(s) |
|---|---|
| A01 Conflicting keys | SDD-013 |
| A02 Dashboard context loss | SDD-049, SDD-052, SDD-068 |
| A03 Blocking previews | SDD-044, SDD-054 |
| A04 Selection drift | SDD-047, SDD-052 |
| A05 Fixed geometry/Unicode | SDD-050, SDD-053, SDD-098 |
| A06 Stale picker | SDD-060 |
| A07 Missing automatic activity/reporting | SDD-070, SDD-072, SDD-075, SDD-077, SDD-089 |
| A08 Kill unexpectedly requeues | SDD-033, SDD-034, SDD-037 |
| A09 Retry evidence/late finish | SDD-027, SDD-032, SDD-036 |
| A10 Cross-project tmux collisions | SDD-028 |
| A11 Session presence mistaken for liveness | SDD-035, SDD-072 |
| A12 Invisible dependency blocking | SDD-025, SDD-051 |
| A13 Missing initialization/recovery UX | SDD-018, SDD-065 |
| A14 Frozen/ambiguous project root | SDD-015 |
| A15 Technical form/lost drafts | SDD-061–064 |
| A16 Provider/default drift | SDD-016 |
| A17 No-op optional IDs | SDD-052 |
| A18 Redraw/poll amplification | SDD-048, SDD-089, SDD-091 |
| A19 Permanent sequence holes | SDD-020–022 |
| A20 Unbounded recovery/framing | SDD-078–082, SDD-085, SDD-091 |
| A21 Push registration/process overhead | SDD-014, SDD-090 |
| A22 Nonatomic/unvalidated edits | SDD-024 |
| A23 Invalid priority reordering | SDD-026 |
| A24 Exit/report/verification conflation | SDD-036, SDD-055 |
| A25 Silent isolation fallback | SDD-030, SDD-062 |
| A26 Unsupported interactive mode | SDD-016, SDD-052; optional SDD-107 |
| A27 Notification duplication/reason drift | SDD-067 |
| A28 Stale locks/partial publication | SDD-018–023 |
| A29 Spawn/config inconsistencies | SDD-029, SDD-031 |
| A30 Health/package drift | SDD-094, SDD-096 |
| A31 Envelope/path validation | SDD-017, SDD-024, SDD-075 |
| A32 Ignores/statusline integration | SDD-008, SDD-095–096 |

## 6. Start sequence and implementation handoff

Start with **SDD-001**, then **SDD-002 and SDD-003**, followed by the **SDD-004 runtime experiment** and **SDD-005/006 contracts**. SDD-007/008 complete the foundation. Adopt canonical namespaces and compatibility before routing v3 data through the new runtime. The first user-visible review milestone is SDD-009–016; it makes no live-telemetry release claim.

The next mandatory risk milestones are recovered control transactions (SDD-022), safe lifecycle operations (SDD-033–036), migration publication (SDD-041), and genuine external delivery (SDD-086). Workspace features can be reviewed with fixtures after their dependencies pass. Complete production binding and end-to-end telemetry at SDD-089/093 before measuring release claims.

When handing an atomic task to an implementer, include its ID/card, referenced requirement, completed dependency evidence, current plugin path and fixture command. Return a focused diff plus verification evidence and any newly discovered contract ambiguity. A failed feasibility experiment or conflict with the source specification must result in an explicit spec/decision-record revision before dependent implementation continues; it must not become a silent scope reduction.

Deferred scope remains the source specification's: autonomous planning/retry policies, a new orchestrator model, remote/shared boards, multiplayer editing and merge automation. Optional provider-native or runtime integrations do not block completion of generic local worker observability, but must not be advertised before their own cards pass.
