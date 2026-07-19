#!/usr/bin/env python3
"""Run player detail scraping in short resumable batches."""

from __future__ import annotations

import argparse
import signal
import sqlite3
import subprocess
import sys
import time
from pathlib import Path


def counts(db_path: Path) -> tuple[int, int, int]:
    with sqlite3.connect(db_path) as conn:
        cur = conn.cursor()
        done = int(
            cur.execute(
                "select count(*) from players where detail_fetched_at is not null"
            ).fetchone()[0]
        )
        total = int(cur.execute("select count(*) from players").fetchone()[0])
        elo = int(
            cur.execute("select count(distinct player_id) from player_ratings").fetchone()[0]
        )
    return done, total, elo


def main() -> int:
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, signal.SIG_IGN)

    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--cookies", required=True)
    parser.add_argument("--sleep", default="1.5")
    parser.add_argument("--batch-size", type=int, default=25)
    parser.add_argument("--pause", type=float, default=5)
    args = parser.parse_args()

    scraper = Path(__file__).with_name("llb_scraper.py")
    db_path = Path(args.db)

    while True:
        done, total, elo = counts(db_path)
        remaining = total - done
        print(
            f"player batch status done={done}/{total} elo={elo} remaining={remaining}",
            flush=True,
        )
        if remaining <= 0:
            return 0
        command = [
            sys.executable,
            str(scraper),
            "--cookies",
            args.cookies,
            "--sleep",
            args.sleep,
            "--db",
            str(db_path),
            "player-details",
            "--limit",
            str(min(args.batch_size, remaining)),
        ]
        result = subprocess.run(command, check=False, start_new_session=True)
        if result.returncode != 0:
            print(f"player batch failed returncode={result.returncode}", flush=True)
        time.sleep(args.pause)


if __name__ == "__main__":
    raise SystemExit(main())
