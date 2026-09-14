# aiswarm.nvim

A persistent Neovim workspace and a local tmux control plane for agent tasks. This repository is the standalone plugin: install `aiswarm.nvim`, call `require("aiswarm")`, and use `:AISwarm` or the `aiswarm` CLI.

The core architecture is implemented, but release acceptance is incomplete. Read the [implementation audit](docs/aiswarm-implementation-audit.md) and [remediation SDD plan](docs/aiswarm-remediation-sdd-plan.md) for confirmed gaps, remaining validation and task dependencies.

## Installation

Use [examples/lazy.lua](examples/lazy.lua), replacing `<owner>`:

```lua
{ "<owner>/aiswarm.nvim", main = "aiswarm", dependencies = { "folke/snacks.nvim" }, cmd = { "AISwarm" }, opts = {} }
```

The plugin finds its bundled `bin/aiswarm`. Add this checkout's `bin/` to your shell PATH for CLI use. Run `:checkhealth aiswarm`, then `:AISwarm`; `:help aiswarm` describes commands and keys.

Requires Bash 3.2+, tmux 3.2+, jq, and Neovim 0.10.4+; git enables worktree isolation. Workers and streams run in clean headless Neovim processes, so the scheduler machine also needs Neovim (`AISWARM_NVIM` overrides discovery). Schema-v2 execution additionally needs GNU timeout. Minimum-version and Linux release validation remain outstanding. snacks.nvim is an external dependency; historical checks used commit `882c996c`.

## Quickstart

```sh
export PATH="/absolute/path/to/aiswarm.nvim/bin:$PATH"
cd /path/to/project
aiswarm init
echo "Say hello and write the report" | aiswarm add --title "hello"
aiswarm scheduler start
aiswarm status
aiswarm stream --once --history 50
```

The default `mock` provider spends no tokens. [scripts/aiswarm-quickstart.sh](scripts/aiswarm-quickstart.sh) exercises this flow in a disposable directory. Opening the workspace never creates a board; creation is explicit.

Tasks progress from queued to running, then succeeded, failed or cancelled. Each execution has its own attempt ID, frozen configuration, output and report paths. Cancel stops work; retry queues another execution and retains earlier evidence. Reports label completeness separately from the execution outcome; agent-reported verification is not independently verified testing.

## Editor

```lua
require("aiswarm").setup({
  root = nil, -- explicit board path, else AISWARM_ROOT, else nearest .aiswarm
  ui = { layout = "float", width = 0.92, height = 0.86, icons = "unicode", motion = false, quiet_after_s = 60 },
  telemetry = { enabled = true, heartbeat_ms = 5000, flush_ms = 100, reconcile_ms = 10000 },
  notify = { completed = true, failed = true, input_required = true, started = false, progress = false },
})
```

Some configuration switches are validated but not fully connected to runtime behavior; the audit identifies them. The workspace has responsive task, inspector and activity panes. Inspector tabs cover Overview, Activity, Output, Report, Files and Attempts. The composer supports visual-range context, inline errors, drafts and queued-task editing. Remaining navigation, history, rotation and project-switch defects are tracked in the remediation plan.

| Key / command | Action |
| --- | --- |
| `<leader>Aa` / `:AISwarm` | Open workspace |
| `<leader>Ap` / `:AISwarm pick` | Task picker |
| `<leader>An` / `:[range]AISwarm new` | Composer |
| `<leader>Al` / `:AISwarm activity` | Activity surface |
| `<leader>Ar` / `:AISwarm results` | Attempt reports |
| `:AISwarm inspect`, `output`, `report`, `attach`, `cancel`, `retry` | Selected task, explicit ID, or picker |
| `:AISwarm scheduler start`, `stop`, `pause`, `resume` | Scheduler control |
| `:AISwarm project open <root>` | Explicit board switch |
| `:AISwarm init`, `migrate --dry-run`, `health` | Board creation, migration inventory, diagnostics |

Within the workspace: Enter inspects, `g` attaches, `n` creates, `e` edits, `x` cancels, `r` retries, `?` opens actions and `q` closes. `<leader>A` mappings are supplied by the example lazy spec. `require("aiswarm").statusline()` returns cached counts; see the example for lualine/which-key integration. `User AISwarmEvent` is the sole control-event hook.

## Boards and CLI

New boards live at `.aiswarm/`. Discovery searches ancestors; explicit editor `root` or `AISWARM_ROOT` selects any existing board path. Include `.aiswarm/` in each project's ignores. The CLI currently handles `--root` reliably for `init`; use `AISWARM_ROOT` for other commands until the routing gap is repaired.

Schema-v2 storage remains supported internally for inspection and migration through the same canonical package. Existing data is never renamed or moved automatically. Select an existing board with `AISWARM_ROOT=/absolute/board/path` or `:AISwarm project open /absolute/board/path`, then run `aiswarm migrate --dry-run`. Migration provides backups, staged conversion, resume and rollback, but concurrent-writer protection still needs remediation. Internal `aiswarm.legacy.*` modules describe storage compatibility, not another installable plugin.

The v3 CLI includes `add`, `set --expect-revision`, `move`, `cancel`, `retry`, `dispatch`, `scheduler`, `snapshot`, `stream`, `ack`, `logs`, `progress`, `report-event`, `briefing`, `retention`, `migrate` and `doctor`. Its command reference lives in [doc/aiswarm.txt](doc/aiswarm.txt) and `lua/aiswarm/runtime/commands.lua`; top-level CLI help still needs schema-aware routing. Retained v2 command spellings operate under `aiswarm`; `kill` means cancel and requeue.

Only `AISWARM_*` environment variables are read: root, provider, WIP, tick, timeout, worktrees, runtime path, dedicated tmux socket, executable overrides and retention caps. Board defaults and worker timing propagation need the consistency fixes described in the audit.

Generic output, worker heartbeats and explicit progress are available. Provider-native events, interactive input and named orchestrator delivery are **not implemented** (SDD-101–107; the native Cursor task was dropped). The registry retains a generic `cursor-agent` executable entry. `stream`/`ack` and briefings provide an external consumer interface today.

## Repository and development

| Path | Responsibility |
| --- | --- |
| `lua/aiswarm/` | Public client, session/store/transport, UI and bundled runtime modules |
| `plugin/`, `doc/`, `examples/` | Single command entry point, help, installation integrations |
| `bin/` | `aiswarm`, `aiswarm-push`, `aiswarm-progress` |
| `runtime/` | Clean CLI and worker bootstraps; mock provider |
| `tests/`, `scripts/` | Isolated suites, fixtures, benchmark and terminal checks |
| `docs/` | Specification, historical plan, ADRs, evidence, current audit and remediation |

```sh
bash scripts/test-aiswarm.sh --suite core --suite compatibility
bash scripts/validate-aiswarm-plan.sh
```

The runner uses disposable boards and a private tmux socket. Set `AISWARM_TEST_SNACKS` if the dependency is outside its default location. Historical evidence references missing generated artifacts; strict plan validation currently fails and must not be bypassed to claim release acceptance. Real-terminal evidence recorded so far covers macOS only.

[LICENSE](LICENSE) covers the client and added runtime code under MIT. The bundled Bash control-plane body retains its public domain / CC0 notice; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
