#!/usr/bin/env bash
# Validate docs/aiswarm-implementation-sdd-plan.md and docs/aiswarm-evidence (SDD-008).
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN=""
for c in "$REPO" "$REPO/lua/myPlugins/aiswarm.nvim" "$REPO/lua/myPlugins/hive.nvim"; do [ -f "$c/tests/plan_validator.lua" ] && { PLUGIN="$c"; break; }; done
[ -n "$PLUGIN" ] || { echo "validator not found" >&2; exit 2; }
NVIM_BIN="${AISWARM_NVIM:-$(command -v nvim)}"
exec "$NVIM_BIN" --clean --headless --noplugin -u NONE -i NONE -n -l "$PLUGIN/tests/plan_validator.lua" \
  "${PLAN:-$REPO/docs/aiswarm-implementation-sdd-plan.md}" "${EVIDENCE:-$REPO/docs/aiswarm-evidence}" "$@"
