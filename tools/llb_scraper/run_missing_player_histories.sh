#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRAPER="$ROOT_DIR/tools/llb_scraper/llb_scraper.py"
IMPORTER="$ROOT_DIR/tools/llb_scraper/sqlite_to_mysql.py"

DB="${LLB_HISTORY_DB:-$ROOT_DIR/data/llb_player_history_fix.sqlite3}"
COOKIES="${LLB_HISTORY_COOKIES:-$ROOT_DIR/data/llb_cookies.txt}"
SLEEP="${LLB_HISTORY_SLEEP:-0.7}"
LIMIT="${LLB_HISTORY_LIMIT:-100}"
PHP_CONFIG="${LLB_PHP_CONFIG:-/var/www/www-root/data/www/llb.panfilius.ru/llb_api_config.php}"

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

missing_ids() {
  php -r '
    $cfg = require $argv[1];
    $limit = (int)$argv[2];
    $pdo = new PDO(
      "mysql:host={$cfg["host"]};port={$cfg["port"]};dbname={$cfg["database"]};charset=utf8mb4",
      $cfg["user"],
      $cfg["password"],
      [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $sql = "SELECT p.id
            FROM players p
            WHERE p.id <> 3942478
              AND (
                p.elo IS NOT NULL
                OR EXISTS (SELECT 1 FROM player_ratings r WHERE r.player_id = p.id)
              )
              AND NOT EXISTS (
                SELECT 1 FROM player_tournament_entries e WHERE e.player_id = p.id
              )
            ORDER BY COALESCE(p.elo, 0) DESC, p.id DESC
            LIMIT {$limit}";
    foreach ($pdo->query($sql) as $row) {
      echo $row["id"]."\n";
    }
  ' "$PHP_CONFIG" "$LIMIT"
}

mkdir -p "$(dirname "$DB")" "$ROOT_DIR/data/logs"
export_mysql_from_php_config

mapfile -t IDS < <(missing_ids)
if [[ "${#IDS[@]}" -eq 0 ]]; then
  echo "missing player histories: none"
  exit 0
fi

ARGS=()
for id in "${IDS[@]}"; do
  ARGS+=(--id "$id")
done

echo "missing player histories started at $(date -Is), ids=${#IDS[@]}, limit=$LIMIT"
python3 "$SCRAPER" \
  --db "$DB" \
  --cookies "$COOKIES" \
  --sleep "$SLEEP" \
  player-tournaments "${ARGS[@]}"

python3 "$IMPORTER" "$DB"
echo "missing player histories finished at $(date -Is)"
