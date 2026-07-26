#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRAPER="$ROOT_DIR/tools/llb_scraper/llb_scraper.py"

IDS_FILE="${1:?ids file required}"
DB="${LLB_HISTORY_DB:-$ROOT_DIR/data/history_worker.sqlite3}"
COOKIES="${LLB_HISTORY_COOKIES:-$ROOT_DIR/data/llb_cookies.txt}"
SLEEP="${LLB_HISTORY_SLEEP:-0.8}"
CHUNK_SIZE="${LLB_HISTORY_CHUNK_SIZE:-50}"
PYTHON_BIN="${LLB_HISTORY_PYTHON:-}"

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
  elif [[ -x /usr/local/bin/python3 ]]; then
    PYTHON_BIN="/usr/local/bin/python3"
  else
    echo "python3 not found" >&2
    exit 1
  fi
fi

if [[ ! -f "$IDS_FILE" ]]; then
  echo "ids file not found: $IDS_FILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$DB")" "$ROOT_DIR/data/logs"

ALL_IDS=()
while IFS= read -r id; do
  ALL_IDS+=("$id")
done < <(grep -E '^[0-9]+$' "$IDS_FILE" | awk '!seen[$0]++')

TOTAL="${#ALL_IDS[@]}"
if [[ "$TOTAL" -eq 0 ]]; then
  echo "player history ids: none"
  exit 0
fi

echo "player history worker started at $(now_iso), ids=$TOTAL, db=$DB, chunk=$CHUNK_SIZE, python=$PYTHON_BIN"
offset=0
while [[ "$offset" -lt "$TOTAL" ]]; do
  ARGS=()
  end=$((offset + CHUNK_SIZE))
  if [[ "$end" -gt "$TOTAL" ]]; then
    end="$TOTAL"
  fi
  for ((i=offset; i<end; i++)); do
    ARGS+=(--id "${ALL_IDS[$i]}")
  done
  echo "player history chunk $((offset + 1))-$end/$TOTAL at $(now_iso)"
  "$PYTHON_BIN" "$SCRAPER" \
    --db "$DB" \
    --cookies "$COOKIES" \
    --sleep "$SLEEP" \
    player-tournaments "${ARGS[@]}"
  offset="$end"
done
echo "player history worker finished at $(now_iso), ids=$TOTAL"
