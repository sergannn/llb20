#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT_DIR/data/archive_shards/results"
SERVER_DIR="/root/llb_mobile_scraper/data/archive_shards/results"
SERVER="root@77.222.47.218"

mkdir -p "$OUT_DIR"

pull_one() {
  local name="$1"
  local ssh="$2"
  local remote_dir="$3"
  local remote_db="$4"
  rsync -az "$ssh:$remote_dir/$remote_db" "$OUT_DIR/$name.sqlite3"
}

pull_one panfilius root@77.222.47.218 /root/llb_mobile_scraper data/archive_worker/archive_panfilius.sqlite3
pull_one postagents root@77.222.46.176 /root/llb_mobile_scraper data/archive_worker/archive_postagents.sqlite3
pull_one yandex sergannn@81.26.187.108 /home/sergannn/llb_mobile_scraper data/archive_worker/archive_yandex.sqlite3
pull_one liza ubuntu@46.226.106.210 /home/ubuntu/llb_mobile_scraper data/archive_worker/archive_liza.sqlite3
pull_one imac ser@sers-iMac.local /Users/ser/llb_mobile_scraper data/archive_worker/archive_imac.sqlite3
pull_one timeweb eco27@vh436.timeweb.ru /home/e/eco27/llb_mobile_scraper_archive data/archive_worker/archive_timeweb.sqlite3

ssh "$SERVER" "mkdir -p '$SERVER_DIR'"
rsync -az "$OUT_DIR/" "$SERVER:$SERVER_DIR/"
ssh "$SERVER" "cd /root/llb_mobile_scraper && eval \"\$(php -r '
  \$cfg=require \"/var/www/www-root/data/www/llb.panfilius.ru/llb_api_config.php\";
  foreach ([\"LLB_MYSQL_HOST\"=>\"host\",\"LLB_MYSQL_PORT\"=>\"port\",\"LLB_MYSQL_DATABASE\"=>\"database\",\"LLB_MYSQL_USER\"=>\"user\",\"LLB_MYSQL_PASSWORD\"=>\"password\"] as \$env=>\$key) {
    echo \"export \".\$env.\"=\".escapeshellarg((string)\$cfg[\$key]).\";\\n\";
  }
')\" && python3 tools/llb_scraper/sqlite_to_mysql.py $SERVER_DIR/*.sqlite3"
