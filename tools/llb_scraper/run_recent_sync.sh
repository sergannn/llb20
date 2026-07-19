#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRAPER="$ROOT_DIR/tools/llb_scraper/llb_scraper.py"
IMPORTER="$ROOT_DIR/tools/llb_scraper/sqlite_to_mysql.py"

DB="${LLB_SYNC_DB:-$ROOT_DIR/data/llb_recent_sync.sqlite3}"
COOKIES="${LLB_SYNC_COOKIES:-$ROOT_DIR/data/llb_cookies.txt}"
SLEEP="${LLB_SYNC_SLEEP:-1.2}"
PHP_CONFIG="${LLB_PHP_CONFIG:-/var/www/www-root/data/www/llb.panfilius.ru/llb_api_config.php}"

NEXT_PAGES="${LLB_SYNC_NEXT_PAGES:-5}"
ONLINE_PAGES="${LLB_SYNC_ONLINE_PAGES:-3}"
RESULT_PAGES="${LLB_SYNC_RESULT_PAGES:-8}"
DETAIL_LIMIT="${LLB_SYNC_DETAIL_LIMIT:-600}"
MATCH_LIMIT="${LLB_SYNC_MATCH_LIMIT:-600}"
PLAYER_PAGES="${LLB_SYNC_PLAYER_PAGES:-1}"
PLAYER_DETAIL_LIMIT="${LLB_SYNC_PLAYER_DETAIL_LIMIT:-0}"

mkdir -p "$(dirname "$DB")" "$(dirname "$COOKIES")" "$ROOT_DIR/data/logs"

run_scraper() {
  python3 "$SCRAPER" \
    --db "$DB" \
    --cookies "$COOKIES" \
    --sleep "$SLEEP" \
    "$@"
}

export_mysql_from_php_config() {
  if [[ -f "$PHP_CONFIG" ]]; then
    eval "$(
      php -r '
        $cfg = require $argv[1];
        foreach ([
          "LLB_MYSQL_HOST" => "host",
          "LLB_MYSQL_PORT" => "port",
          "LLB_MYSQL_DATABASE" => "database",
          "LLB_MYSQL_USER" => "user",
          "LLB_MYSQL_PASSWORD" => "password",
        ] as $env => $key) {
          if (isset($cfg[$key])) {
            echo "export ".$env."=".escapeshellarg((string)$cfg[$key]).";\n";
          }
        }
      ' "$PHP_CONFIG"
    )"
  fi
}

echo "recent sync started at $(date -Is)"

if [[ "$PLAYER_PAGES" != "0" ]]; then
  run_scraper players --limit-pages "$PLAYER_PAGES"
fi

if [[ "$PLAYER_DETAIL_LIMIT" != "0" ]]; then
  run_scraper player-details --limit "$PLAYER_DETAIL_LIMIT"
fi

run_scraper tournaments --kind next --limit-pages "$NEXT_PAGES"
run_scraper tournaments --kind online --limit-pages "$ONLINE_PAGES"
run_scraper tournaments --kind results --limit-pages "$RESULT_PAGES"

for kind in next online results; do
  run_scraper tournament-details --force --source-kind "$kind" --limit "$DETAIL_LIMIT"
done

for kind in next online results; do
  run_scraper matches --force --replace-existing --source-kind "$kind" --limit-competitions "$MATCH_LIMIT"
done

export_mysql_from_php_config
python3 "$IMPORTER" --replace-competition-data "$DB"

echo "recent sync finished at $(date -Is)"
