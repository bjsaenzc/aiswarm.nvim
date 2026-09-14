#!/usr/bin/env bash
# aiswarm test entry point (SDD-001).
#
#   bash scripts/test-aiswarm.sh --task SDD-023
#   bash scripts/test-aiswarm.sh --suite core
#   bash scripts/test-aiswarm.sh --list
#
# Runs the plugin's Lua test cases in a clean headless Neovim (no user config,
# no shada) inside a disposable sandbox: private HOME/XDG dirs, private TMPDIR,
# private Neovim log, a dedicated tmux socket and a PATH that contains only the
# tools the suite needs (no real provider CLI is reachable). It never touches
# the caller's board, tmux server or repository files.
#
# Exit codes: 0 all selected cases passed (unverified cases allowed)
#             1 at least one case failed
#             2 unknown task/suite or empty selection
#             3 runner/environment error
set -u

usage() { sed -n '2,15p' "$0"; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN=""
# standalone checkout (plugin at the repository root) or nested under lua/myPlugins/
for candidate in "$REPO" "$REPO/lua/myPlugins/aiswarm.nvim"; do
  [ -f "$candidate/tests/runner.lua" ] && { PLUGIN="$candidate"; break; }
done
[ -n "$PLUGIN" ] || { echo "test-aiswarm: no plugin tests directory found" >&2; exit 3; }

NVIM_BIN="${AISWARM_NVIM:-$(command -v nvim || true)}"
[ -n "$NVIM_BIN" ] && [ -x "$NVIM_BIN" ] || { echo "test-aiswarm: nvim not found (set AISWARM_NVIM)" >&2; exit 3; }

KEEP=false
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --keep) KEEP=true; shift;;
    *) ARGS+=("$1"); shift;;
  esac
done

# Discover optional dependencies before HOME is replaced.
SNACKS="${AISWARM_TEST_SNACKS:-}"
if [ -z "$SNACKS" ]; then
  for candidate in "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/snacks.nvim" "$HOME/.local/share/nvim/lazy/snacks.nvim"; do
    [ -d "$candidate/lua/snacks" ] && { SNACKS="$candidate"; break; }
  done
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
ART="$REPO/artifacts/aiswarm"
RUN="$ART/$RUN_ID"
mkdir -p "$RUN/home" "$RUN/xdg/config" "$RUN/xdg/data" "$RUN/xdg/state" "$RUN/xdg/cache" "$RUN/tmp" "$RUN/bin" \
  || { echo "test-aiswarm: cannot create $RUN" >&2; exit 3; }

# Minimal PATH: only the directories of the tools the suite needs.
tool_dirs=""
for tool in "$NVIM_BIN" tmux jq bash git timeout gtimeout sh env awk sed; do
  p=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$p" ] || continue
  d=$(dirname "$p")
  case ":$tool_dirs:" in *":$d:"*) ;; *) tool_dirs="${tool_dirs:+$tool_dirs:}$d";; esac
done
SANDBOX_PATH="$RUN/bin:$tool_dirs:/usr/bin:/bin"

TMUX_SOCKET="aiswarm-test-$$"

# Scrub inherited environment that could leak the user's board or session.
for v in $(env | awk -F= '/^AISWARM_/{print $1}'); do
  case "$v" in AISWARM_NVIM|AISWARM_TEST_SNACKS|AISWARM_TEST_CHILD_TIMEOUT_MS|AISWARM_BENCH_*) ;; *) unset "$v";; esac
done
unset TMUX TMUX_PANE NVIM NVIM_LISTEN_ADDRESS VIMINIT MYVIMRC EXINIT

export HOME="$RUN/home"
export XDG_CONFIG_HOME="$RUN/xdg/config" XDG_DATA_HOME="$RUN/xdg/data"
export XDG_STATE_HOME="$RUN/xdg/state" XDG_CACHE_HOME="$RUN/xdg/cache"
# Unix sockets (tmux, Neovim servers) need a short path: a private dir under /tmp, removed at exit.
SOCKDIR="$(mktemp -d /tmp/aisw-t.XXXXXX)"; mkdir -p "$SOCKDIR/run"
export TMUX_TMPDIR="$SOCKDIR" XDG_RUNTIME_DIR="$SOCKDIR/run" TMPDIR="$RUN/tmp" NVIM_LOG_FILE="$RUN/nvim.log" PATH="$SANDBOX_PATH"
export AISWARM_TEST_RUN_DIR="$RUN" AISWARM_TEST_RUN_ID="$RUN_ID" AISWARM_TEST_PLUGIN="$PLUGIN"
export AISWARM_TEST_REPO="$REPO" AISWARM_TEST_TMUX_SOCKET="$TMUX_SOCKET" AISWARM_TEST_SNACKS="$SNACKS"
export AISWARM_NVIM="$NVIM_BIN"
export GIT_CEILING_DIRECTORIES="$RUN"   # fixtures never discover the host repository as their git root

cleanup() {
  tmux -L "$TMUX_SOCKET" kill-server >/dev/null 2>&1 || true
  pkill -9 -f "runtime/worker.lua --root $RUN" >/dev/null 2>&1 || true   # workers that outlived their tmux server
  pkill -9 -f "aiswarm.nvim/runtime/cli.lua events --since" >/dev/null 2>&1 || true   # legacy followers started by tests
  rm -rf "$SOCKDIR"
  if ! $KEEP; then rm -rf "$RUN/home" "$RUN/xdg" "$RUN/tmp" "$RUN/bin"; fi
}
trap cleanup EXIT

"$NVIM_BIN" --clean --headless --noplugin -u NONE -i NONE -n \
  -l "$PLUGIN/tests/runner.lua" "${ARGS[@]+"${ARGS[@]}"}"
code=$?
echo "evidence: $RUN/evidence.json"
exit $code
