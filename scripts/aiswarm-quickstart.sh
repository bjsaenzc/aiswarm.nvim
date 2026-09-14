#!/usr/bin/env bash
# Runs the documented mock quickstart in a disposable directory and verifies the outcome (SDD-096).
#   bash scripts/aiswarm-quickstart.sh [--keep]
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$REPO/lua/myPlugins/aiswarm.nvim"; [ -d "$PLUGIN" ] || PLUGIN="$REPO"   # nested or standalone checkout
export PATH="$PLUGIN/bin:$PATH"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/aiswarm-quickstart.XXXXXX")"
SOCKDIR="$(mktemp -d /tmp/aisw-qs.XXXXXX)"   # Unix socket paths must stay short
export TMUX_TMPDIR="$SOCKDIR" AISWARM_TMUX_SOCKET="qs-$$" AISWARM_MOCK_SLEEP="${AISWARM_MOCK_SLEEP:-1}"
cleanup() { tmux -L "$AISWARM_TMUX_SOCKET" kill-server >/dev/null 2>&1 || true; rm -rf "$SOCKDIR"; [ "${1:-}" = keep ] || rm -rf "$WORK"; }
trap 'cleanup ${KEEP:-}' EXIT
[ "${1:-}" = --keep ] && KEEP=keep
cd "$WORK"
echo "== aiswarm init"
aiswarm init
echo "== aiswarm add"
id=$(echo "Say hello and write the report" | aiswarm add --title "hello")
echo "queued $id"
echo "== aiswarm scheduler start"
aiswarm scheduler start --tick 1
echo "== waiting for $id"
aiswarm wait "$id" --timeout 60
aiswarm status
echo "== aiswarm stream --once --history 50"
aiswarm stream --once --history 50 | head -n 2
echo
# JSON key order is not stable, so parse with jq (required by the launcher anyway) instead of grep
state=$(aiswarm show "$id" --json | jq -r '.task.state // empty')
[ -n "$state" ] || state=$(aiswarm snapshot --json | jq -r --arg id "$id" '.tasks[] | select(.id == $id) | .state')
aiswarm scheduler stop
echo "== result: $id $state"
[ "$state" = succeeded ] || { echo "quickstart failed: expected succeeded, got $state" >&2; exit 1; }
