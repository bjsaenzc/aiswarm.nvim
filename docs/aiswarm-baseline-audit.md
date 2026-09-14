# AISwarm baseline audit archive

Historical baseline: `c7c636a`, 2026-09-13. This document preserves the 32 finding IDs referenced by the technical specification and original SDD plan. It describes the predecessor schema-v2 implementation at that baseline, not the current standalone package. Original source coordinates belonged to a different repository layout and are intentionally not presented as current file links.

The baseline consisted of a Bash file-board/tmux control plane, a singleton polling/event client, a floating dashboard/picker/form, a push helper and local editor integration. Task identity also served as execution identity; logs/reports were overwritten across retries, and session ownership was not board-scoped. There was no plugin-local verification harness at that baseline.

For the current module map, verification and unresolved implementation gaps, read the [implementation audit](aiswarm-implementation-audit.md). Baseline findings below are historical observations retained for traceability, not fresh reproductions.

| Finding / priority | Historical observation and proposed direction |
| --- | --- |
| A01 / P0 | Buffer-local Git mappings shadow AISwarm picker/results. `<leader>Hr` resets a hunk in tracked code. Move aiswarm to a distinct uppercase `<leader>A` group, with no default legacy key aliases. |
| A02 / P1 | Enter closes the board and changes tmux sessions; tail/add/results also close it. Enter on a non-task row can close it without an action. Prefer a persistent inspector and explicit attach. |
| A03 / P1 | Peek and picker preview synchronously wait up to 1.5 seconds. File/report fallback reads are also unbounded. Use cancellable async reads with selection tokens and size limits. |
| A04 / P0 | Full rerender changes the row-to-ID map without preserving selected ID. A status transition can retarget the next action. Anchor selection/actions to task and attempt IDs. |
| A05 / P1 | Fixed-width columns/separator/footer, unbounded titles, byte-oriented padding and hardcoded extmark spans complicate narrow terminals and Unicode. Some spans assume a three-byte glyph even when the glyph has a different encoding. Use display-cell measurement and byte-accurate spans. |
| A06 / P1 | Open task pickers do not subscribe to updates; kill can leave stale entries/preview. Reconcile items while preserving query and selected ID. |
| A07 / P1 | Output capture and progress events are separate; the runner never derives progress from output or schedules heartbeats. There is no combined live log feed or persisted latest progress projection. |
| A08 / P0 | “Kill” means immediately requeue, so a running scheduler can launch it again next tick. Define separate cancel and retry operations with explicit outcomes. |
| A09 / P0 | Reruns overwrite the same transcript/rendered prompt; an existing report is accepted even if the new run writes none. No attempt identity fences a late finish callback. Add immutable attempt paths and generation checks. |
| A10 / P0 | `agent-<id>` is global to the tmux server. Different projects collide; `down` kills every `agent-*` session. Namespace sessions by board/attempt and verify ownership before mutation. |
| A11 / P0 | `remain-on-exit` retains a session after process death; reaper and `live` only check session existence. A worker wrapper crash can remain active indefinitely. Track process/pane health separately from inspectability. |
| A12 / P1 | Missing/failed dependencies and cycles remain indistinguishable from runnable queued work and can wait forever. Validate dependency graph and expose blocked reasons. |
| A13 / P1 | No in-editor initialization/start flow. Missing board, empty queue, paused scheduler and absent scheduler are poorly distinguished. Form/picker require a successful snapshot first. |
| A14 / P1 | Root freezes at first use; cwd change does not switch projects. `setup()` switching also resets unspecified options. Add an explicit project session API and project indicator. Canonicalize symlinks consistently with push. |
| A15 / P1 | Seven technical fields precede the prompt; all errors are toasts; form closes with a wipe buffer; ID allocation is guessed client-side. Introduce prompt-first composition, durable drafts and inline field errors; let backend allocate IDs. |
| A16 / P1 | GUI defaults to claude, CLI to mock. UI's hardcoded providers differ from doctor's executable names (`cursor` vs `cursor-agent`). Centralize stable provider IDs, discovery and effective defaults. |
| A17 / P1 | Commands accept optional IDs then silently do nothing without one. Resolve contextual selection or open a task picker. |
| A18 / P1 | Every event redraws the whole dashboard; background snapshots run every 3 seconds even when hidden. High-volume log events would amplify work. Separate event ingestion, projections and throttled visible rendering. |
| A19 / P0 | Counter is saved before journal append. A crash between them can create a permanent sequence hole and stall ordered delivery. Journal recovery and explicit generation/gap handling are prerequisites for reliable telemetry. |
| A20 / P1 | Recovery scans the full journal and returns all matching lines through a short-command timeout. Pending events and partial-line buffer have no bounds; follower stderr is discarded. Add paging, bounds, backoff, retention-aware cursors and connection diagnostics. |
| A21 / P1 | One registration file targets the latest editor; a registration failure is not retried until setup. Every push forks a process. Followers can support other editors; push should not carry high-volume logs. |
| A22 / P0 | Ready-state check and edit are not serialized with dispatch; set applies fields incrementally and omits creation validation. Reproduced invalid provider/negative timeout acceptance. Require revision-checked atomic edits. |
| A23 / P1 | Move-first turns priority 0 into -1, contradicting form/add validation. String sorting pads only up to six digits, so very large priorities can sort unexpectedly. Normalize/rebalance numeric queue ordering. |
| A24 / P1 | Exit 0 alone means done; verification/report completeness is not checked. Cost grep is best effort, and claude requests text. Show execution outcome separately from report quality and verification claims; unknown cost is not zero. |
| A25 / P1 | Requested worktree silently falls back to shared cwd when prerequisites/config are absent. Display and validate effective isolation before queueing. Shared mode requires explicit selection in the proposed composer. |
| A26 / P1 | `mode` is stored but unused; headless processes cannot be assumed to accept a message pasted into a pane. Provider capabilities must gate messaging/input actions. |
| A27 / P2 | Multiple notification channels can announce the same completion. `notify.orphaned` has no matching built-in event: reaper emits `failed` with `rc=orphaned`. Centralize type/reason handling and notification policy. |
| A28 / P1 | SIGKILL can leave stale lock directories; add publishes prompt then task without a crash recovery transaction. A failed add before init can create a partial board's locks directory. Diagnose and recover owned stale state; do not label staged publication fully crash-atomic. |
| A29 / P1 | Spawn failure after the active move has no rollback in dispatch. Effective WIP/config values in `json` reflect the invoking CLI environment, not an authoritative scheduler configuration record. Record scheduler identity/config and structured dispatch failures. |
| A30 / P2 | Version minimums are documented rather than fully verified; provider capability checks are only executable discovery; health messages/documentation references drift. Add versioned capability probes and package docs/licenses before release. |
| A31 / P1 | Arbitrary event extras merge over reserved keys. Most string/path arguments outside add/kill receive weaker validation. Use a validated versioned envelope and allowlisted payload; validate task IDs before using them in paths/session targets. |
| A32 / P2 | Runtime board files are not ignored here; available AISwarm statusline is not integrated. Include repository-specific ignore and lightweight statusline changes in the migration inventory. |
