#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRAPER="$ROOT_DIR/tools/llb_scraper/llb_scraper.py"
IMPORTER="$ROOT_DIR/tools/llb_scraper/sqlite_to_mysql.py"

DB="${LLB_ARCHIVE_DB:-$ROOT_DIR/data/llb_archive_participants.sqlite3}"
COOKIES="${LLB_ARCHIVE_COOKIES:-$ROOT_DIR/data/llb_cookies.txt}"
SLEEP="${LLB_ARCHIVE_SLEEP:-0.6}"
LIMIT="${LLB_ARCHIVE_LIMIT:-200}"
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

missing_archive_ids() {
  php -r '
    $cfg = require $argv[1];
    $limit = (int)$argv[2];
    $pdo = new PDO(
      "mysql:host={$cfg["host"]};port={$cfg["port"]};dbname={$cfg["database"]};charset=utf8mb4",
      $cfg["user"],
      $cfg["password"],
      [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $sql = "SELECT DISTINCT e.tournament_id
            FROM player_tournament_entries e
            LEFT JOIN archive_tournament_participants a ON a.tournament_id = e.tournament_id
            LEFT JOIN archive_tournament_fetches f ON f.tournament_id = e.tournament_id
            LEFT JOIN tournaments t ON t.id = e.tournament_id
            WHERE e.tournament_id IS NOT NULL
              AND COALESCE(t.comp_id, 0) = 0
              AND a.tournament_id IS NULL
              AND f.tournament_id IS NULL
            ORDER BY e.tournament_id DESC
            LIMIT {$limit}";
    foreach ($pdo->query($sql) as $row) {
      echo $row["tournament_id"]."\n";
    }
  ' "$PHP_CONFIG" "$LIMIT"
}

mkdir -p "$(dirname "$DB")" "$ROOT_DIR/data/logs"
export_mysql_from_php_config

mapfile -t IDS < <(missing_archive_ids)
if [[ "${#IDS[@]}" -eq 0 ]]; then
  echo "missing archive participants: none"
  exit 0
fi

ARGS=()
for id in "${IDS[@]}"; do
  ARGS+=(--id "$id")
done

echo "missing archive participants started at $(date -Is), limit=$LIMIT"
python3 "$SCRAPER" \
  --db "$DB" \
  --cookies "$COOKIES" \
  --sleep "$SLEEP" \
  archive-participants \
  "${ARGS[@]}"

python3 "$IMPORTER" "$DB"
echo "missing archive participants finished at $(date -Is)"
