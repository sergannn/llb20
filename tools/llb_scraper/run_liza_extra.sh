#!/bin/sh
cd "$HOME/llb_mobile_scraper" || exit 1
exec python3 tools/llb_scraper/llb_scraper.py \
  --cookies data/llb_cookies.txt \
  --sleep 1.5 \
  --db data/player_work_shards/elo_liza_extra.sqlite3 \
  player-details
