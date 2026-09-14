#!/usr/bin/env bash
# SDD-100 demonstration from one disposable board: both names, a task journey with cancel/retry and
# report, live logs/progress on the stream, and an external consumer recovering across a restart.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$REPO/lua/myPlugins/aiswarm.nvim"; [ -d "$PLUGIN" ] || PLUGIN="$REPO"   # nested or standalone checkout
export PATH="$PLUGIN/bin:$PATH"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/aiswarm-demo.XXXXXX")"; SOCKDIR="$(mktemp -d /tmp/aisw-demo.XXXXXX)"
export TMUX_TMPDIR="$SOCKDIR" AISWARM_TMUX_SOCKET="demo-$$" AISWARM_QUIET_LEGACY=1
export AISWARM_PROVIDER_EXEC_mock="$PLUGIN/tests/fixtures/providers/fake-provider" AISWARM_FAKE_PROGRESS="$PLUGIN/bin/aiswarm-progress" AISWARM_FAKE_TICK_MS=100
cleanup() { tmux -L "$AISWARM_TMUX_SOCKET" kill-server >/dev/null 2>&1 || true; pkill -9 -f "runtime/worker.lua --root $WORK" >/dev/null 2>&1 || true; rm -rf "$SOCKDIR"; [ "${KEEP:-}" = 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT
cd "$WORK"; export AISWARM_ROOT="$WORK/.aiswarm"
step() { printf '\n== %s\n' "$*"; }
step "canonical init, legacy name reads the same board"
aiswarm init --name demo
hive json | head -c 200; echo
step "queue through both names"
id1=$(echo "first" | aiswarm add --title "first task"); id2=$(echo "second" | hive add --title "second task" --dep "$id1"); echo "$id1 $id2"
step "run, cancel, retry, report"
AISWARM_FAKE_SCENARIO=quiet AISWARM_FAKE_BARRIER="$WORK/barrier" aiswarm dispatch
sleep 1; aiswarm status
aiswarm cancel "$id1" --grace 1
aiswarm retry "$id1"
AISWARM_FAKE_SCENARIO=progress aiswarm dispatch; aiswarm wait "$id1" --timeout 60
aiswarm status
step "live logs and progress"
aiswarm logs "$id1" --attempt 2 | tail -3
aiswarm stream --once --history 20 --types progress,lifecycle | grep -c '"frame":"event"'
step "external consumer with a restart mid-delivery"
INBOX="$WORK/inbox.jsonl"
run_consumer() { AISWARM_CONSUMER_FAULT="${1:-}" "${AISWARM_NVIM:-nvim}" --clean --headless -u NONE -i NONE -l "$PLUGIN/tests/fixtures/consumer/consumer.lua" --bin "$PLUGIN/bin/aiswarm" --root "$AISWARM_ROOT" --name demo --inbox "$INBOX" --batch 4 --exit-after-idle 1500 2>&1 | tail -1; }
run_consumer after_accept; run_consumer ""
echo "accepted $(wc -l < "$INBOX" | tr -d ' ') events, unique event ids $(grep -o '"event_id":"[^"]*"' "$INBOX" | sort -u | wc -l | tr -d ' ')"
aiswarm consumers | head -c 300; echo
step "briefing for an orchestrator"
aiswarm briefing
step "done"
