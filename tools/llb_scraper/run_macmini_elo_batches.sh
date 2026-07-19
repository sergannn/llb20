#!/bin/sh
cd "/Users/servas/Documents/parsing visa" || exit 1
exec python3 -u tools/llb_scraper/run_player_detail_batches.py \
  --cookies data/llb_cookies.txt \
  --sleep 1.5 \
  --db data/player_work_shards/elo_macmini.sqlite3 \
  --batch-size 25 \
  --pause 5
