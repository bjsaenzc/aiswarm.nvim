# ADR 0001 — Headless Neovim as the v3 worker/stream/control runtime

Task: SDD-004 · Status: **accepted** · Date: 2026-09-14 · Evidence: `bash scripts/test-aiswarm.sh --task SDD-004` (`artifacts/aiswarm/<run>/spike-measurements.json`)

## Question

The specification (§6) proposes small Lua helpers hosted by a clean, headless Neovim for worker I/O collection and stream multiplexing, and asks for a feasibility experiment before dependent work. This record accepts or rejects that runtime and fixes the resource budget.

## Experiment

Prototype: `tests/fixtures/runtime_spike/worker.lua` started as `nvim --clean --headless --noplugin -u NONE -i NONE -n -l worker.lua`. It spawns the fake provider (`tests/fixtures/providers/fake-provider`) in its own process group (`detached=true`), streams stdout/stderr into JSONL records, emits heartbeats, and terminates the provider process group when a cancel request file appears.

| Measurement (macOS 25.6, arm64, Neovim v0.12.0-dev-1781) | Result |
|---|---|
| Clean headless startup to script exit, 10 samples | median 14–16 ms, max 19 ms |
| Sentinel `init.lua` and `plugin/*.lua` in `XDG_CONFIG_HOME` | never executed (marker file absent) |
| Records visible while provider blocked on a barrier | spawned + heartbeats readable before exit |
| Write→read latency, JSONL polled every 10 ms (flood scenario) | p50 ≈ 1–7 ms, p95 ≈ 1–7 ms, max ≈ 7 ms |
| Cancel via request file with a grandchild `sleep` | grandchild terminated; provider exit recorded as signal 15 |
| Ten idle workers | ≈ 12 MiB RSS each (≈ 118 MiB total), idle CPU ≈ 0 % |

## Findings that shape the design

1. **Signals are not a reliable control channel inside Neovim.** Neovim installs its own deadly-signal handler; a `uv.new_signal` handler races it and the process can exit before the provider's exit is recorded. Cancellation therefore uses an explicit `cancel.request` file in the attempt directory, checked by the watchdog timer (50 ms). SIGTERM remains a best-effort fallback only.
2. **`pairs(vim.env)` yields nothing.** Child environments must be built from `vim.fn.environ()`.
3. **Process groups work.** `uv.spawn(..., {detached=true})` puts the provider in its own group; `uv.kill(-pid, sig)` reaches grandchildren. This is the termination primitive for SDD-033/071.
4. Startup cost (~15 ms) is small enough that **every v3 control command may run as `nvim -l runtime/cli.lua`** invoked by the Bash launcher. This lets the backend share `protocol.lua` validators, the journal writer, reducer and cursor codec with the editor instead of re-implementing transactions in Bash 3.2 + jq.

## Decision

- **Accept** headless Neovim as the runtime for: worker bootstrap (`runtime/worker.lua`), stream multiplexer (`aiswarm stream`), and all v3 board control commands (`runtime/cli.lua`). Bash `bin/aiswarm` stays the user-facing launcher and keeps serving **v2 (legacy `.hive` schema) boards through the unchanged v2 code path**; v3 boards are dispatched to the Lua runtime.
- The launcher resolves the Neovim executable absolutely: `$AISWARM_NVIM`, else `command -v nvim`; the editor passes its own `v:progpath`. Missing Neovim is an environment error (exit 4) reported before any task becomes runnable.
- The runtime loads only bundled modules (`lua/aiswarm/**`); never `init.lua`, user plugins, or shada.

## Resource budget (declared before dependent work)

| Budget | Limit |
|---|---|
| Worker RSS, idle | ≤ 40 MiB per worker (measured ≈ 12 MiB) |
| Worker RSS under the reference flood (1 MiB/s aggregate over 10 workers) | ≤ 80 MiB per worker; bounded queues from SDD-070/085 |
| Control command wall time on a cached board | ≤ 250 ms p95 (startup ≈ 15 ms + I/O) |
| Stream reader idle CPU with 10 attempts, 250 ms poll fallback | ≤ 3 % of one core |
| Record→reader latency (local filesystem) | ≤ 500 ms p95 as specified; spike suggests ≤ 50 ms is realistic with fs events/polling |

A later measurement above a limit fails SDD-097; the limit is not to be raised after the fact.

## Consequences

- Standalone v3 workers and streams require Neovim ≥ 0.10.4 on the machine running the scheduler; the docs (SDD-096) and health (SDD-094) state this explicitly.
- The v2 Bash implementation remains for compatibility and migration inventory only; it gains no new features.
