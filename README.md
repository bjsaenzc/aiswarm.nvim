# aiswarm.nvim

A persistent Neovim workspace and a tmux-based control plane for running many agent CLI tasks locally, formerly `hive.nvim`. One board per project, one tmux session per attempt, one replayable stream for the editor and any external orchestrator.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim): copy [examples/lazy.lua](examples/lazy.lua) into your plugin specs and replace `<owner>`. The plugin depends on [snacks.nvim](https://github.com/folke/snacks.nvim) and finds its own `bin/aiswarm` launcher; put `bin/` on your `PATH` to use the CLI from a shell.

```lua
{ "<owner>/aiswarm.nvim", main = "aiswarm", dependencies = { "folke/snacks.nvim" }, cmd = { "AISwarm" }, opts = {} }
```

After installing: `:checkhealth aiswarm`, then `:AISwarm`. `:help aiswarm` covers setup, commands, keys, compatibility and migration.

## Overview

**aiswarm** (formerly `hive.nvim`) turns tmux into a small local multi-agent control plane and gives it a persistent Neovim workspace. You queue tasks on a file **board**; a scheduler runs each attempt in its **own tmux session** through a clean headless Neovim **worker**; the worker captures output, heartbeats and explicit progress into per-attempt journals; the editor and any external process follow one replayable **stream**.

```text
   Neovim (aiswarm.nvim)                                  external orchestrator process
   workspace · picker · composer · toasts · lualine       aiswarm stream --follow --consumer NAME | aiswarm ack
        ▲ stream frames (control + telemetry)                        ▲
        └────────────── aiswarm stream --follow ─────────────────────┘
                              │ reads
   board (.aiswarm/ or an upgraded .hive/)
     board.json                     identity, schema 3, journal generation
     control/journal.jsonl          write-ahead control journal (tasks, attempts, scheduler)
     control/tasks|attempts/*.json  projections (rebuilt from the journal on recovery)
     prompts/<id>/r<rev>.md         immutable prompt revisions
     attempts/<attempt-id>/         stdout/stderr segments, telemetry.jsonl, activity.json, inbox/, report.md
        ▲ lock + validated transactions        ▲ one telemetry writer per attempt
   aiswarm scheduler loop  ──dispatch──▶  tmux aiswarm-<board>-<attempt> ──▶ nvim -l runtime/worker.lua ──▶ provider CLI
```

| Piece | What it is |
| --- | --- |
| `bin/aiswarm` (Bash launcher) | Resolves the board (`--root`, `$AISWARM_ROOT`, `$HIVE_ROOT`, discovery), keeps serving **legacy v2 boards** with the unchanged v2 implementation, and hands **v3 boards** to `runtime/cli.lua`. `bin/hive` and `bin/hive-push` forward to it. |
| `runtime/cli.lua`, `runtime/worker.lua` (headless Neovim) | v3 control commands (init, add, set, move, cancel, retry, dispatch, scheduler, snapshot, stream, ack, logs, migrate, doctor) and the supervised worker. They load only the bundled `lua/aiswarm/**` modules, never your config. See [ADR 0001](docs/aiswarm-decisions/0001-worker-runtime.md). |
| `lua/aiswarm/` (Neovim client) | `store`, `transport` (stream client), `backend` (async typed CLI client), `project` (explicit board sessions), `ui/*` (workspace, tasks, inspector, activity, composer, picker, actions, layout), `notify`, `health`; `lua/hive/*` are thin shims. |

### Requirements

- **bash 3.2+**, **tmux ≥ 3.2**, **jq** (legacy boards and the launcher), **git** (optional, worktree isolation) and **Neovim 0.10.4+** on the machine that runs the scheduler: v3 workers and streams are headless Neovim processes (`$AISWARM_NVIM` overrides discovery). GNU `timeout` is only needed for legacy v2 boards; v3 workers enforce deadlines themselves.
- Agent CLIs for real work: `claude`, `codex`, `gemini`, `aider` (Cursor is not a target provider). The **`mock`** provider (the default) spends no tokens. Provider-native events (tool calls, usage, input requests) are **not** enabled: every provider gets generic output, heartbeat and explicit-progress telemetry.
- Neovim-side: **snacks.nvim** (verified against commit `882c996c`). `:checkhealth aiswarm` verifies everything.

### Quickstart (mock provider, zero tokens)

```sh
export PATH="$HOME/.local/share/nvim/lazy/aiswarm.nvim/bin:$PATH"   # or wherever this repository is checked out
cd ~/some/project
aiswarm init                              # explicit; opening the workspace never creates a board
echo "Say hello and write the report" | aiswarm add --title "hello"
aiswarm scheduler start                   # tmux session aiswarm-<board>-scheduler
aiswarm status                            # or: nvim, then <leader>Aa
aiswarm stream --once --history 50        # what an external orchestrator would read
```

`scripts/aiswarm-quickstart.sh` runs exactly this in a disposable directory and checks the outcome. In Neovim: `<leader>Aa` opens the workspace; with no board it offers `c` create, `o` open, `h` health; `n` composes a task (mock is preselected), `S` starts the scheduler when it is stopped.

### Task lifecycle

`queued → running → succeeded | failed | cancelled`. A queued task can be edited (revision-checked), reordered (numeric priorities, rebalanced instead of going negative) and cancelled. Dispatch reserves an immutable **attempt** (own id, ordinal, frozen config, own artifact paths) and spawns the worker; spawn failures release capacity with one recorded outcome. `cancel` stops the attempt's own process tree and never requeues; `retry` creates a fresh attempt while earlier logs and reports stay readable. Dependencies are validated (missing, self, cycles) and a failed upstream shows as an explicit blocker rather than an invented failure. A dead worker is detected by process identity, not by a lingering tmux pane, and becomes `Failed: orphaned`.

### What a worker sees

The rendered prompt carries the mission/interfaces/decisions context, dependency reports, the exact attempt report path, and an absolute progress helper: `aiswarm-progress --phase testing --message "…"` (board/task/attempt come from the environment). Cooperation improves the Activity view; heartbeats and raw output are captured regardless. Report sections are checked for completeness (`complete`, `incomplete`, `missing`); a model's "tests passed" is displayed as *reported*, never as verified.

### Environment variables

`AISWARM_ROOT` (`HIVE_ROOT` accepted with one warning), `AISWARM_PROVIDER` (default `mock`), `AISWARM_WIP`, `AISWARM_TICK`, `AISWARM_TIMEOUT`, `AISWARM_MAX_TURNS`, `AISWARM_WORKTREES` (git worktree directory; required for `--isolation worktree`), `AISWARM_NVIM`, `AISWARM_TMUX_SOCKET`, `AISWARM_PROVIDER_EXEC_<id>` (executable override), retention caps `AISWARM_RAW_CAP_BYTES`, `AISWARM_TELEMETRY_CAP_BYTES`, `AISWARM_RETENTION_DAYS`.

### CLI reference (v3 boards)

```text
aiswarm init [--name N] [--wip N] [--worktrees DIR]      aiswarm add [--id ID] [--title T] [--provider P] [--dep ID]... [--priority N] [--timeout S] [--isolation shared|worktree] [--file F]
aiswarm set <id> --expect-revision N [fields]           aiswarm move <id> --first|--last|--before ID|--after ID
aiswarm cancel <id> [--grace S]   aiswarm retry <id>    aiswarm snapshot | status | show <id> | json (v2-shaped)
aiswarm scheduler status|start|stop|pause|resume        aiswarm dispatch | reconcile | attach <id> | peek <id> | wait <id> | gc | down
aiswarm stream [--follow] [--cursor C] [--consumer NAME] [--types lifecycle,progress,...] [--task ID] [--history N]
aiswarm ack --consumer NAME --cursor C                  aiswarm logs <id> [--attempt N] [--stream stdout|stderr] [--offset B] [--limit B] [--follow]
aiswarm progress --task ID --attempt A --phase P --message M   aiswarm report-event --path FILE   aiswarm briefing   aiswarm retention [--dry-run]
aiswarm migrate --dry-run | migrate | migrate --resume | migrate --rollback     aiswarm doctor [--json]
```

Legacy commands (`events`, `tail`, `kill`, `pause`, `resume`, `up`, `loop`, `go`) keep working on both schemas; `kill` prints a warning because it still means cancel **and requeue**.

### Neovim side

See [examples/lazy.lua](examples/lazy.lua) for the lazy.nvim spec (`main = "aiswarm"`, lazy-loads on `:AISwarm`, the `:Hive*` aliases and the `<leader>A` keys). Configuration (all validated; invalid values fail before any job or file is created):

```lua
require("aiswarm").setup({
  bin = nil,                                    -- defaults to this checkout's bin/aiswarm; a name on PATH or an absolute path
  root = nil,                                   -- explicit board; else $AISWARM_ROOT, $HIVE_ROOT, nearest .aiswarm/.hive
  ui = { layout = "float", width = 0.92, height = 0.86, icons = "unicode", motion = false, quiet_after_s = 60 },
  telemetry = { enabled = true, heartbeat_ms = 5000, flush_ms = 100, reconcile_ms = 10000 },
  notify = { completed = true, failed = true, input_required = true, started = false, progress = false },
  compat = { hive_commands = true, hive_events = false },
})
```

- **Project sessions**: the board is chosen once per session (`:AISwarm project` shows/switches it; `:cd` only suggests a switch). Both `.aiswarm/` and `.hive/` in one directory require an explicit choice.
- **Legacy boards** open read-mostly with a banner; `:AISwarm migrate --dry-run` inventories, `--upgrade` converts in place after a verified backup (`.hive/migration/`), `--resume`/`--rollback` handle interruptions. Migration never starts the scheduler.
- **Workspace** (`:AISwarm`): responsive breakpoints from the interior size (wide ≥110×28: list + inspector + activity tray; medium: list + inspector; narrow: one pane at a time, `Backspace` returns; minimal <40×12: picker only). Sections Running / Attention / Queued / Finished; every state has text, icons are optional (`icons = "ascii"`). The inspector has Overview, Activity, Output (bounded, `f` pauses view following, `G` jumps to the end, `o` opens the full transcript), Report (labelled missing/incomplete/synthesized), Files (with provenance) and Attempts tabs; `p` pins it. Actions capture task/attempt/revision and report "Task changed; review current state" instead of hitting another task.
- **Composer**: prompt-first buffer with Title/Provider/Isolation (advanced fields folded under `<C-a>`), inline diagnostics, autosaved project-scoped drafts (`<Esc>` keeps them, `<C-q>` discards), `<C-e>` exports the old `#:` form, `:AISwarm new --legacy` imports one.
- **Notifications**: actionable failures, completions and input requests only, aggregated in bursts, never replayed on reconnect; the attention badge persists until you view the task. **Statusline**: `require("aiswarm").statusline()` is cached (no I/O) and wired into lualine.
- **Hooks**: `User AISwarmEvent` (normalized control record); `User HiveEvent` only with `compat.hive_events = true`.

### Gotchas

- Standalone v3 workers need Neovim on the scheduler machine; `aiswarm doctor` and `:checkhealth aiswarm` say so explicitly.
- `.aiswarm/` and `.hive/` boards belong in every project's ignore file (this repository ignores them).
- Native provider events, an interactive input channel and delivery into a named orchestrator runtime are **not implemented** (plan tasks SDD-101–107); the generic telemetry, the `stream`/`ack` subscription, briefings and copy/export are what ships.
- Real-terminal validation was recorded on macOS only; see [docs/aiswarm-evidence/](docs/aiswarm-evidence/).


## Keys and commands

| Key / command                                                   | Action                                                                                                                                 |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `<leader>Aa` / `:AISwarm`                                       | Workspace: task list + inspector + activity. `⏎` inspect, `t` output, `R` report, `g` attach, `n` new, `e` edit, `x` cancel, `r` retry, `P` pause, `?` actions, `q` close |
| `<leader>Ap` / `:AISwarm pick`                                  | Live task picker: `⏎` inspect, `<C-t>` output, `<C-r>` report, `<C-x>` cancel, `<C-y>` retry, `<C-g>` attach                             |
| `<leader>An` (n, v) / `:[range]AISwarm new`                     | Composer; a visual selection / range becomes prompt context. `<C-s>` or `:w` queues, `<Esc>` keeps a draft                              |
| `<leader>Al` / `:AISwarm activity`                              | Combined activity feed                                                                                                                 |
| `<leader>Ar` / `:AISwarm results`                               | Reports picker (one entry per task attempt)                                                                                            |
| `:AISwarm inspect\|output\|report\|attach\|cancel\|retry [id]` | Act on the selected task, or open the picker when no id can be resolved                                                                |
| `:AISwarm scheduler start\|stop\|pause\|resume`, `:AISwarm project`, `:AISwarm init`, `:AISwarm migrate --dry-run`, `:AISwarm health` | Scheduler control, board selection, explicit board creation, legacy upgrade, `:checkhealth aiswarm` |
| `:Hive*` (ten legacy commands)                                  | Aliases kept for one compatibility release; `:HiveKill` keeps its cancel-and-requeue meaning and says so                               |

The mappings live under `<leader>A`; the plugin installs no other global keys. `:help aiswarm` documents everything below in detail.


## Repository layout

| Path | Contents |
| --- | --- |
| `lua/aiswarm/`, `plugin/`, `doc/` | The Neovim client, its command registration and `:help aiswarm` / `:help hive` |
| `bin/` | `aiswarm` launcher (Bash 3.2), `aiswarm-progress` helper, transitional `hive` / `hive-push` aliases |
| `runtime/` | `cli.lua` (v3 control commands) and `worker.lua` (the supervised headless worker); `mock-provider` |
| `tests/` | The automated suites and fixtures (`bash scripts/test-aiswarm.sh --suite core`) |
| `scripts/` | Test harness, plan validator, quickstart, demo, benchmark and real-terminal screenshot drivers |
| `docs/` | Technical spec, ADRs (`aiswarm-decisions/`), the implementation plan and its evidence (`aiswarm-evidence/`), release checklist, the original hive.nvim audit |

## Development

`bash scripts/test-aiswarm.sh --suite core` runs the suites in a sandbox (a clean headless Neovim, an isolated board, a dedicated tmux socket; nothing of yours is touched). `--task SDD-NNN --record` writes an evidence record; `bash scripts/validate-aiswarm-plan.sh` checks the plan against the evidence. snacks.nvim is discovered under `~/.local/share/nvim/lazy/snacks.nvim` or via `AISWARM_TEST_SNACKS`.

## Licensing

`LICENSE` (MIT) covers the Neovim client under `lua/`, `plugin/`, `doc/`, `runtime/` and `tests/`. `bin/aiswarm` descends from the public-domain / CC0 `hive` control plane; see `THIRD_PARTY_NOTICES.md`.
