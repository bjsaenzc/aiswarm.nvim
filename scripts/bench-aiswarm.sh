#!/usr/bin/env bash
# Runs the exact SDD-097 workload: 10 workers, 1,000 tasks, 200 progress records/s, 1 MiB/s output, 10 minutes.
#   bash scripts/bench-aiswarm.sh [seconds]
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AISWARM_BENCH_SECONDS="${1:-600}" AISWARM_BENCH_WORKERS=10 AISWARM_BENCH_TASKS=1000 AISWARM_BENCH_TASK_SECONDS="${AISWARM_BENCH_TASK_SECONDS:-60}"
export AISWARM_TEST_CHILD_TIMEOUT_MS=$(( (AISWARM_BENCH_SECONDS + 300) * 1000 ))
exec bash "$REPO/scripts/test-aiswarm.sh" --task SDD-097 --record
