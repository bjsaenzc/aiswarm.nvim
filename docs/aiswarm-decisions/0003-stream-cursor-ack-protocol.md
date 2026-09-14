# ADR 0003 — Stream, cursor and acknowledgement contracts

Task: SDD-006 · Status: **accepted** · Date: 2026-09-14 · Requirement: R03, R12 · Fixtures: `tests/fixtures/protocol/`

## Schemas (`schema_version` 1)

All records share the envelope `{schema_version, board_id, event_id, observed_at, type, level?, task_id?, attempt_id?, payload}`. Reserved envelope keys can never be supplied by a payload; emitters reject them (SDD-017). Unknown additive fields are ignored by readers; unknown `type` values are displayed but never change lifecycle state. A major `schema_version` above the reader's support puts the connection into the **incompatible** state.

| Family | Ordering key | Producer |
|---|---|---|
| control (`task.*`, `attempt.started/finished`, `scheduler.changed`) | `(board_id, journal_generation, control_seq)` | control journal writer only (ADR 0002) |
| telemetry (`agent.*`, `telemetry.warning`) | `(attempt_id, stream_generation, attempt_seq)` | the attempt's single telemetry writer |
| raw output | `(attempt_id, stream, segment, byte offset)` | worker log writer |
| synthetic (`stream.gap`, `stream.status`) | none; carries the affected source | stream reader |

`event_id` is `<board_id>:c:<generation>:<control_seq>` for control and `<attempt_id>:<stream_generation>:<attempt_seq>` for telemetry; consumers deduplicate on it.

Ordering across stdout/stderr and across attempts is **by observed timestamp, then source id, then source sequence**; this is deterministic but is not a claim of causal order between independent workers. Control order is preserved exactly.

## Stream frames (`aiswarm stream`)

```
{"frame":"hello","schema_version":1,"board_id":…,"journal_generation":1,"capabilities":{…},"resumed_from":null|cursor}
{"frame":"snapshot","control_seq":N,"tasks":[…],"attempts":[…],"scheduler":{…},
 "activity":{"<attempt_id>":{…projection…,"checkpoint":{"stream_generation":"1","attempt_seq":37}}},"next_cursor":C}
{"frame":"event","event":{…},"next_cursor":C}
{"frame":"gap","source":"control"|"attempt:<id>","from":…,"to":…,"reason":"retention"|"generation"|"quarantine","next_cursor":C}
{"frame":"status","state":"live"|"end"|"reconnecting","next_cursor":C}
{"frame":"error","code":"invalid_cursor"|"resync_required"|"incompatible"|"wrong_board","message":…}
```

Frames are JSON Lines. A frame may not exceed 256 KiB; the decoder discards an oversized partial frame, emits one diagnostic and resynchronizes at the next newline (SDD-078).

## Checkpoint acquisition (no attachment gap)

1. Take the control lock briefly; run recovery; read `applied.json`; read every projection and every attempt's `activity.json` with its own checkpoint. Release the lock.
2. Emit `hello`, then `snapshot` whose `next_cursor` encodes those positions.
3. Replay every control record with `control_seq > snapshot.control_seq` and every telemetry record after each attempt checkpoint, then follow. Records appended between step 1 and step 3 are therefore delivered, never lost; an attempt created during attach is discovered by its `attempt.started` control record and its telemetry starts from sequence 0.

## Cursor

Opaque to consumers: base64url of `{"v":1,"board":<board_id>,"control":{"g":1,"seq":42},"attempts":{"<attempt_id>":{"g":"1","seq":37}},"logs":{"<attempt_id>/stdout":{"segment":1,"offset":8192}}}`.

- Advances **only after a frame is fully written**; the cursor in an `event` frame is the position after that event.
- **Filters** (`--types`, `--task`, `--attempt`, `--since`) apply at emission; scanned-but-filtered records still advance the cursor. Reconnecting with different filters therefore does not re-deliver records that earlier filters skipped; to see them, resume from an older cursor or request `--history N`.
- `--history N` (≤ 200) replays the most recent N feed records before following, labelled `historical:true`; it never triggers notifications and never moves any consumer bookmark.
- A cursor from another board → `wrong_board`. A generation older than the journal's → `resync_required` with a `gap` frame and a fresh snapshot. A `control.seq` beyond the committed sequence (future/impossible) → `invalid_cursor`. Retention that evicted a telemetry segment → `gap` frame for that source, then continue.

## Acknowledgement (`aiswarm ack --consumer NAME --cursor C`)

- `NAME` matches `^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$` and is board-scoped.
- The cursor must decode, belong to this board and generation, and not exceed committed history (`control.seq ≤ committed`, `attempts[*].seq ≤ written`); otherwise the ack is rejected (exit 3) and the bookmark is untouched.
- Bookmarks are **monotonic per source**: an ack whose positions are behind the stored bookmark on any source is rejected as stale. Stored with tmp + rename; a crash leaves the old or new file, never a mix.
- Acking is the consumer's responsibility **after** downstream acceptance. Opening a stream never acknowledges anything. Two consumers never share a bookmark.

## Contract walkthrough

| Case | Outcome |
|---|---|
| concurrent attach while records are appended | included by snapshot or replayed after it (checkpoint rule) |
| new attempt unseen by cursor | discovered from control; telemetry from seq 0 |
| records filtered out | cursor still advances; documented above |
| duplicate replay after reconnect | delivered again with the same `event_id`; consumers deduplicate |
| cursor from another board | `error wrong_board`, nothing delivered |
| ack beyond delivered history | rejected, exit 3 |
| reconnect with different filters | new filters apply from the cursor onward only |

Round-trip examples live in `tests/fixtures/protocol/valid/*.json`; rejected shapes in `tests/fixtures/protocol/invalid/*.json` with the expected error code.
