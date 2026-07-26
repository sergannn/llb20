#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIMIT="${LLB_HISTORY_LOOP_LIMIT:-5}"
SLEEP_BETWEEN="${LLB_HISTORY_LOOP_SLEEP_BETWEEN:-10}"
MAX_BATCHES="${LLB_HISTORY_LOOP_MAX_BATCHES:-0}"
RETRY_SLEEP="${LLB_HISTORY_LOOP_RETRY_SLEEP:-60}"
LOG_DIR="$ROOT_DIR/data/logs"
mkdir -p "$ROOT_DIR/data/player_history_fix" "$LOG_DIR"

batch=0
while true; do
  batch=$((batch + 1))
  if [[ "$MAX_BATCHES" -gt 0 && "$batch" -gt "$MAX_BATCHES" ]]; then
    echo "player history gap loop reached max batches=$MAX_BATCHES at $(date -Is)"
    exit 0
  fi

  stamp="$(date +%Y%m%d%H%M%S)"
  db="$ROOT_DIR/data/player_history_fix/batch_${stamp}.sqlite3"
  batch_log="$LOG_DIR/player_history_gap_batch_${stamp}.log"
  echo "player history gap loop batch=$batch limit=$LIMIT db=$db at $(date -Is)"

  set +e
  LLB_HISTORY_DB="$db" \
    LLB_HISTORY_LIMIT="$LIMIT" \
    "$ROOT_DIR/tools/llb_scraper/run_missing_player_histories.sh" \
    2>&1 | tee "$batch_log"
  status="${PIPESTATUS[0]}"
  set -e

  if grep -q "missing player histories: none" "$batch_log"; then
    echo "player history gap loop complete: no candidates at $(date -Is)"
    exit 0
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "player history gap loop warning: batch failed with status=$status at $(date -Is), retry in ${RETRY_SLEEP}s" >&2
    sleep "$RETRY_SLEEP"
    continue
  fi

  sleep "$SLEEP_BETWEEN"
done
