# ADR 0002 — Control journal transaction boundaries and on-disk layout

Task: SDD-005 · Status: **accepted** · Date: 2026-09-14 · Requirement: R03

## On-disk layout (schema 3)

```
<root>/                      .aiswarm/ for new boards; an upgraded .hive/ keeps its path
  board.json                 {schema_version:3, board_id (UUID), journal_generation, name, created_at, scheduler_defaults}
  control/
    journal.jsonl            committed control records, append-only, one JSON object per line
    seq                      sidecar hint: last committed control_seq (cache, never authority)
    applied.json             {seq} — last control_seq whose projections are fully published
    tasks/<task_id>.json     projection of the current task record
    attempts/<attempt_id>.json projection of the attempt record
    scheduler.json           scheduler instance projection (identity, heartbeat, paused, wip, effective config)
    consumers/<name>.json    durable consumer bookmarks (SDD-083)
    quarantine/<ts>.jsonl    uncommitted tail fragments moved out of the journal during recovery
  locks/control.d/owner.json mkdir lock; owner identity {pid, pid_start, host, acquired_at, purpose}
  locks/migration.marker     present only during migration (SDD-039)
  prompts/<task_id>/r<revision>.md   immutable prompt text per task revision
  attempts/<attempt_id>/     immutable per-attempt artifacts (config.json, prompt.rendered.md,
                             stdout.<segment>.log, stderr.<segment>.log, telemetry.jsonl, telemetry.seq,
                             activity.json, inbox/, report.md, cancel.request, worker.json)
  context/                   MISSION/DECISIONS/INTERFACES (unchanged from v2)
  migration/                 backups and manifest (SDD-039/041)
```

Task IDs match `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` and attempt IDs are UUIDv4; both are validated before any path is built (SDD-017).

## Control record

Every control record is a complete, self-describing envelope. The `payload` carries the **post-state** of every entity the transaction changed, so applying a record is idempotent (write the projection file) and replaying a prefix of the journal twice yields identical projections (SDD-021).

```json
{"schema_version":1,"board_id":"…","journal_generation":1,"control_seq":42,"event_id":"…:1:42",
 "txn":{"id":"…","index":1,"count":2,"last":false},
 "observed_at":"2026-09-14T03:00:00.000Z","type":"task.queued","task_id":"T-014","attempt_id":null,
 "actor":"editor:pid","payload":{"task":{…full task record…},"reason":null}}
```

## Lock ownership and liveness

`locks/control.d` is acquired with `mkdir` (atomic on every supported filesystem). The owner immediately writes `owner.json` (tmp + rename). Acquisition waits up to 10 s in 25 ms steps. A contender that finds an existing lock reads `owner.json`:

- **no owner file for > 2 s** → treated as a crash between mkdir and write; recover.
- **owner pid alive and pid start time matches** → keep waiting; a live owner is never stolen.
- **owner pid dead, or alive with a different start time (PID reuse)** → recover: rename the lock dir to `locks/stale-<ts>.d` (atomic; two contenders cannot both succeed) and retry.
- **different host / unknown identity** → do not delete; fail with an actionable timeout error naming the owner.

Migration acquires the same lock and additionally writes `locks/migration.marker`; compliant writers refuse mutations while the marker exists.

## Transaction order (write path, under the lock)

1. **Recover** (always first, also before snapshots): read the journal tail; a trailing line without `\n` or that does not parse is moved to `quarantine/`, and the journal is truncated to the last complete record. If the last complete record has `txn.last == false`, every trailing record of that `txn.id` is quarantined too (a transaction's records are contiguous at the tail by construction). Then read the last valid record's `control_seq`; if `seq` (sidecar) disagrees, the journal wins and the sidecar is rewritten. If `applied.json.seq` is behind, replay records `(applied, committed]` into projections, then publish `applied.json`.
2. **Validate** the mutation against the recovered projections (revision, state, dependency graph, provider, paths). Failure leaves the board unchanged.
3. **Stage artifacts** that the record references (prompt revision file, attempt config) with tmp + rename. An unreferenced staged file is garbage, never state.
4. **Allocate** `control_seq` values from the last committed record (+1 per record), build all records of the transaction with `txn.count` and `txn.last`.
5. **Append + flush**: one `write` of the whole transaction buffer to the journal opened `O_APPEND`, then `fsync`. The transaction is **committed** exactly when the `fsync` returns.
6. **Sidecar**: write `seq` (tmp + rename). A crash before this leaves a stale hint that recovery ignores.
7. **Projection**: write every changed entity file (tmp + rename), then `applied.json` (tmp + rename). A crash inside this step is repaired by step 1 on the next command.
8. Release the lock (`rmdir`).

Batch framing decision: **one operation = one transaction = one buffered append**. Legacy kill→cancel-and-requeue (SDD-037) is one transaction of two records.

## Crash-point walkthrough

| Crash point | Recovery outcome |
|---|---|
| after `mkdir`, before `owner.json` | lock dir without owner file ages out (2 s) and is renamed away; no state change occurred |
| after validation/staging, before append | staged prompt/config file unreferenced; journal unchanged; no sequence consumed |
| mid-append (partial line or partial txn) | tail quarantined; committed seq is the last complete txn; the same seq numbers are reused **only** for records that were never committed (never for a committed one) |
| after `fsync`, before sidecar | sidecar stale; recovery reads the journal, rewrites sidecar, replays projections; nothing lost |
| after sidecar, before/inside projections | `applied.json` behind; replay `(applied, committed]` (idempotent); nothing lost |
| after projections, before `applied.json` | replay rewrites identical files; harmless |
| after `applied.json`, before `rmdir` | lock recovered by liveness check; state complete |

Process-crash behavior above is tested with fault injection (SDD-020/022). **Power-loss durability** additionally depends on `fsync` semantics of the filesystem and the directory entry rename; this ADR claims process-crash safety, and only that, until a power-loss test exists.

## Permitted rollback

Rollback is only ever applied to **uncommitted** tail records (quarantine). Committed records are never removed; a mistaken operation is undone by a new compensating record.
