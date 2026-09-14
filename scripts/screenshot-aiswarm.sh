#!/usr/bin/env bash
# Real-terminal screenshots for SDD-098: runs an actual Neovim TUI inside tmux panes of exact sizes,
# drives it with keystrokes, and captures the rendered screen as text.
#   bash scripts/screenshot-aiswarm.sh [out-dir]
# Output: <out-dir>/<size>-<variant>-<step>.txt plus index.txt with the keystrokes used.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$REPO/lua/myPlugins/aiswarm.nvim"; [ -d "$PLUGIN" ] || PLUGIN="$REPO"   # nested or standalone checkout
OUT="${1:-$REPO/artifacts/aiswarm/screens-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"
NVIM_BIN="${AISWARM_NVIM:-$(command -v nvim)}"
SNACKS="${AISWARM_TEST_SNACKS:-$HOME/.local/share/nvim/lazy/snacks.nvim}"
SOCK="aiswarm-shot-$$"
SOCKDIR="$(mktemp -d /tmp/aisw-shot.XXXXXX)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/aiswarm-shot.XXXXXX")"
export TMUX_TMPDIR="$SOCKDIR" AISWARM_TMUX_SOCKET="$SOCK" AISWARM_QUIET_LEGACY=1 AISWARM_NVIM="$NVIM_BIN"
export AISWARM_PROVIDER_EXEC_mock="$PLUGIN/tests/fixtures/providers/fake-provider" AISWARM_FAKE_TICK_MS=50 AISWARM_FAKE_PROGRESS="$PLUGIN/bin/aiswarm-progress"
T() { tmux -L "$SOCK" "$@"; }
cleanup() { T kill-server >/dev/null 2>&1 || true; pkill -9 -f "runtime/worker.lua --root $WORK" >/dev/null 2>&1 || true; rm -rf "$SOCKDIR"; }
trap cleanup EXIT

# ---- fixture board: running (quiet), failed, blocked, queued, succeeded, cancelled, with a CJK/emoji title
ROOT="$WORK/.aiswarm"
export AISWARM_ROOT="$ROOT"
B="$PLUGIN/bin/aiswarm"
"$B" init --name screenshots >/dev/null
echo "upstream that fails" | AISWARM_FAKE_SCENARIO=failure "$B" add --id T-001 --title "Refresh integration" >/dev/null
echo "success" | "$B" add --id T-002 --title "Add session refresh 日本語 タイトル 🚀" >/dev/null
echo "quiet" | "$B" add --id T-003 --title "Update login copy (long title to test truncation behaviour in narrow panes)" >/dev/null
echo "blocked" | "$B" add --id T-004 --title "Wire refresh UI" --dep T-001 >/dev/null
echo "queued" | "$B" add --id T-005 --title "Write docs" >/dev/null
echo "cancel me" | "$B" add --id T-006 --title "Cancelled experiment" >/dev/null
"$B" cancel T-006 >/dev/null
BARRIER="$WORK/barrier"
WRAP="$WORK/provider"; cat > "$WRAP" <<WEOF
#!/usr/bin/env bash
case "\$AISWARM_TASK" in T-001) s=failure;; T-002) s=progress;; T-003) s=quiet;; *) s=success;; esac
exec "$PLUGIN/tests/fixtures/providers/fake-provider" --scenario "\$s" "\$@"
WEOF
chmod +x "$WRAP"
AISWARM_PROVIDER_EXEC_mock="$WRAP" AISWARM_FAKE_BARRIER="$BARRIER" AISWARM_WIP=10 "$B" scheduler start --wip 10 --tick 1 >/dev/null 2>&1
"$B" wait T-001 --timeout 30 >/dev/null 2>&1 || true; "$B" wait T-002 --timeout 30 >/dev/null 2>&1 || true; "$B" wait T-005 --timeout 30 >/dev/null 2>&1 || true
sleep 1; "$B" progress T-003 --phase editing --message "Editing login copy" >/dev/null 2>&1 || true
sleep 1

shot() { # shot <name>  — capture the current screen
  T capture-pane -p -t "=shot:" > "$OUT/$1.txt"
}
run_variant() { # run_variant <cols> <rows> <variant> <extra env...>
  local cols="$1" rows="$2" variant="$3"; shift 3
  local tag="${cols}x${rows}-${variant}"
  T kill-session -t "=shot" >/dev/null 2>&1 || true
  T new-session -d -s shot -x "$cols" -y "$rows" -c "$WORK" \
    -e AISWARM_SHOT_PLUGIN="$PLUGIN" -e AISWARM_SHOT_SNACKS="$SNACKS" -e AISWARM_SHOT_ROOT="$ROOT" -e TMUX_TMPDIR="$SOCKDIR" -e AISWARM_TMUX_SOCKET="$SOCK" "$@" \
    "$NVIM_BIN --clean -u $PLUGIN/tests/fixtures/terminal/init.lua"
  # force the pane to the exact size regardless of the client
  T resize-window -t "=shot:" -x "$cols" -y "$rows" >/dev/null 2>&1 || true
  sleep 2.5
  shot "$tag-01-workspace"
  T send-keys -t "=shot:" j; sleep 0.4; shot "$tag-02-select-next"
  T send-keys -t "=shot:" Enter; sleep 0.6; shot "$tag-03-inspect"
  T send-keys -t "=shot:" ']'; sleep 0.5; shot "$tag-04-activity-tab"
  T send-keys -t "=shot:" ']'; sleep 0.8; shot "$tag-05-output-tab"
  T send-keys -t "=shot:" ']'; sleep 0.8; shot "$tag-06-report-tab"
  T send-keys -t "=shot:" BSpace; sleep 0.4; shot "$tag-07-back"
  T send-keys -t "=shot:" x; sleep 0.6; shot "$tag-08-cancel-confirm"
  T send-keys -t "=shot:" n; sleep 0.4
  T send-keys -t "=shot:" '?'; sleep 0.6; shot "$tag-09-actions-menu"
  T send-keys -t "=shot:" Escape; sleep 0.2; T send-keys -t "=shot:" Escape; sleep 0.4
  T send-keys -t "=shot:" n; sleep 0.8; shot "$tag-10-composer"
  T send-keys -t "=shot:" Escape; sleep 0.3; T send-keys -t "=shot:" Escape; sleep 0.4
  T send-keys -t "=shot:" q; sleep 0.4; shot "$tag-11-closed"
  T send-keys -t "=shot:" ':qa!' Enter; sleep 0.3
  printf '%s: j Enter ] ] ] BSpace x n ? Esc Esc n Esc Esc q\n' "$tag" >> "$OUT/index.txt"
}
: > "$OUT/index.txt"
for size in "140 45" "100 30" "80 24" "60 20" "35 10"; do set -- $size; run_variant "$1" "$2" dark; done
run_variant 140 45 light -e AISWARM_SHOT_BACKGROUND=light
run_variant 140 45 ascii -e AISWARM_SHOT_ICONS=ascii -e AISWARM_SHOT_TRUECOLOR=0
run_variant 110 30 boundary
run_variant 109 30 boundary
run_variant 110 29 boundary
echo "go" > "$BARRIER"
"$B" scheduler stop >/dev/null 2>&1 || true
echo "$OUT"
