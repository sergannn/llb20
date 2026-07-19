#!/bin/sh
cd "/Users/servas/Documents/parsing visa" || exit 1
exec python3 -u tools/llb_scraper/run_tournament_detail_batches.py \
  --cookies data/llb_cookies.txt \
  --sleep 1.5 \
  --db data/llb_local_tournaments.sqlite3 \
  --batch-size 20 \
  --pause 3
