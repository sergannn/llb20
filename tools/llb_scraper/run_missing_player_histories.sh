#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRAPER="$ROOT_DIR/tools/llb_scraper/llb_scraper.py"
IMPORTER="$ROOT_DIR/tools/llb_scraper/sqlite_to_mysql.py"

DEFAULT_PHP_CONFIG="$ROOT_DIR/llb_api_config.php"
if [[ ! -f "$DEFAULT_PHP_CONFIG" ]]; then
  DEFAULT_PHP_CONFIG="/var/www/www-root/data/www/llb.panfilius.ru/llb_api_config.php"
fi

DB="${LLB_HISTORY_DB:-$ROOT_DIR/data/llb_player_history_fix.sqlite3}"
COOKIES="${LLB_HISTORY_COOKIES:-$ROOT_DIR/data/llb_cookies.txt}"
SLEEP="${LLB_HISTORY_SLEEP:-0.7}"
LIMIT="${LLB_HISTORY_LIMIT:-100}"
PHP_CONFIG="${LLB_PHP_CONFIG:-$DEFAULT_PHP_CONFIG}"

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

ensure_history_fetch_table() {
  php -r '
    $cfg = require $argv[1];
    $pdo = new PDO(
      "mysql:host={$cfg["host"]};port={$cfg["port"]};dbname={$cfg["database"]};charset=utf8mb4",
      $cfg["user"],
      $cfg["password"],
      [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $pdo->exec("CREATE TABLE IF NOT EXISTS player_history_fetches (
      player_id INT NOT NULL PRIMARY KEY,
      stats_total INT NOT NULL DEFAULT 0,
      profile_entries_count INT NOT NULL DEFAULT 0,
      fetched_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
  ' "$PHP_CONFIG"
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
    $stats = "CAST(REGEXP_REPLACE(REGEXP_SUBSTR(JSON_UNQUOTE(JSON_EXTRACT(p.detail_json, '\''$.\\\"_sections\\\".\\\"Статистика\\\"'\'')), '\''Турниров[[:space:]]*:[[:space:]]*[0-9]+'\''), '\''[^0-9]'\'', '\'''\'' ) AS UNSIGNED)";
    $sql = "SELECT x.id
            FROM (
              SELECT p.id,
                     COALESCE({$stats}, 0) AS stats_total,
                     COUNT(DISTINCT e.tournament_id) AS profile_entries_count
              FROM players p
              LEFT JOIN player_tournament_entries e
                ON e.player_id = p.id
               AND e.source_page >= 0
               AND e.membership_node_id > 0
              WHERE p.id <> 3942478
                AND NOT EXISTS (
                  SELECT 1 FROM player_history_fetches h WHERE h.player_id = p.id
                )
              GROUP BY p.id
            ) x
            WHERE x.stats_total > 0
              AND x.stats_total > x.profile_entries_count
            ORDER BY (x.stats_total - x.profile_entries_count) DESC, x.id DESC
            LIMIT {$limit}";
    foreach ($pdo->query($sql) as $row) {
      echo $row["id"]."\n";
    }
  ' "$PHP_CONFIG" "$LIMIT"
}

delete_fallback_rows_for_ids() {
  php -r '
    $cfg = require $argv[1];
    $ids = array_slice($argv, 2);
    if (!$ids) {
      exit;
    }
    $pdo = new PDO(
      "mysql:host={$cfg["host"]};port={$cfg["port"]};dbname={$cfg["database"]};charset=utf8mb4",
      $cfg["user"],
      $cfg["password"],
      [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $placeholders = implode(",", array_fill(0, count($ids), "?"));
    $stmt = $pdo->prepare("DELETE FROM player_tournament_entries WHERE source_page < 0 AND player_id IN ({$placeholders})");
    $stmt->execute(array_map("intval", $ids));
    echo "deleted fallback rows=".$stmt->rowCount()."\n";
  ' "$PHP_CONFIG" "$@"
}

record_history_fetches_for_ids() {
  php -r '
    $cfg = require $argv[1];
    $ids = array_slice($argv, 2);
    if (!$ids) {
      exit;
    }
    $pdo = new PDO(
      "mysql:host={$cfg["host"]};port={$cfg["port"]};dbname={$cfg["database"]};charset=utf8mb4",
      $cfg["user"],
      $cfg["password"],
      [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $stats = "CAST(REGEXP_REPLACE(REGEXP_SUBSTR(JSON_UNQUOTE(JSON_EXTRACT(p.detail_json, '\''$.\\\"_sections\\\".\\\"Статистика\\\"'\'')), '\''Турниров[[:space:]]*:[[:space:]]*[0-9]+'\''), '\''[^0-9]'\'', '\'''\'' ) AS UNSIGNED)";
    $select = $pdo->prepare("SELECT COALESCE({$stats}, 0) AS stats_total,
                                    (SELECT COUNT(DISTINCT e.tournament_id)
                                     FROM player_tournament_entries e
                                     WHERE e.player_id = p.id
                                       AND e.source_page >= 0
                                       AND e.membership_node_id > 0) AS profile_entries_count
                             FROM players p WHERE p.id = ?");
    $upsert = $pdo->prepare("INSERT INTO player_history_fetches
                               (player_id, stats_total, profile_entries_count, fetched_at, updated_at)
                             VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                             ON DUPLICATE KEY UPDATE
                               stats_total = VALUES(stats_total),
                               profile_entries_count = VALUES(profile_entries_count),
                               fetched_at = CURRENT_TIMESTAMP,
                               updated_at = CURRENT_TIMESTAMP");
    foreach ($ids as $id) {
      $playerId = (int)$id;
      $select->execute([$playerId]);
      $row = $select->fetch(PDO::FETCH_ASSOC) ?: ["stats_total" => 0, "profile_entries_count" => 0];
      $upsert->execute([$playerId, (int)$row["stats_total"], (int)$row["profile_entries_count"]]);
    }
    echo "recorded history fetches=".count($ids)."\n";
  ' "$PHP_CONFIG" "$@"
}

mkdir -p "$(dirname "$DB")" "$ROOT_DIR/data/logs"
export_mysql_from_php_config
ensure_history_fetch_table

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

delete_fallback_rows_for_ids "${IDS[@]}"
python3 "$IMPORTER" "$DB"
record_history_fetches_for_ids "${IDS[@]}"
echo "missing player histories finished at $(date -Is)"
