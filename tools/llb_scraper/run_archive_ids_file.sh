#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRAPER="$ROOT_DIR/tools/llb_scraper/llb_scraper.py"

IDS_FILE="${1:?ids file required}"
DB="${LLB_ARCHIVE_DB:-$ROOT_DIR/data/archive_worker.sqlite3}"
COOKIES="${LLB_ARCHIVE_COOKIES:-$ROOT_DIR/data/llb_cookies.txt}"
SLEEP="${LLB_ARCHIVE_SLEEP:-0.6}"
CHUNK_SIZE="${LLB_ARCHIVE_CHUNK_SIZE:-100}"

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
  echo "archive ids: none"
  exit 0
fi

echo "archive ids worker started at $(date -Is), ids=$TOTAL, db=$DB, chunk=$CHUNK_SIZE"
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
  echo "archive ids chunk $((offset + 1))-$end/$TOTAL at $(date -Is)"
  python3 "$SCRAPER" \
    --db "$DB" \
    --cookies "$COOKIES" \
    --sleep "$SLEEP" \
    archive-participants "${ARGS[@]}"
  offset="$end"
done
echo "archive ids worker finished at $(date -Is), ids=$TOTAL"
