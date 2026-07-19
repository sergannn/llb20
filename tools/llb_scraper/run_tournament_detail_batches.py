#!/usr/bin/env python3
"""Run tournament detail scraping in resumable batches."""

from __future__ import annotations

import argparse
import sqlite3
import subprocess
import sys
import time
from pathlib import Path


def pending_count(db_path: Path) -> int:
    with sqlite3.connect(db_path) as conn:
        return int(
            conn.execute(
                "SELECT count(*) FROM tournaments WHERE detail_fetched_at IS NULL"
            ).fetchone()[0]
        )


def fetched_counts(db_path: Path) -> tuple[int, int, int]:
    with sqlite3.connect(db_path) as conn:
        detail = int(
            conn.execute(
                "SELECT count(*) FROM tournaments WHERE detail_fetched_at IS NOT NULL"
            ).fetchone()[0]
        )
        comp = int(
            conn.execute(
                "SELECT count(*) FROM tournaments WHERE comp_id IS NOT NULL"
            ).fetchone()[0]
        )
        total = int(conn.execute("SELECT count(*) FROM tournaments").fetchone()[0])
    return detail, comp, total


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--cookies", required=True)
    parser.add_argument("--sleep", default="1.5")
    parser.add_argument("--batch-size", type=int, default=50)
    parser.add_argument("--pause", type=float, default=3.0)
    args = parser.parse_args()

    db_path = Path(args.db)
    scraper = Path(__file__).with_name("llb_scraper.py")

    while True:
        pending = pending_count(db_path)
        detail, comp, total = fetched_counts(db_path)
        print(
            f"batch status detail={detail}/{total} comp={comp} pending={pending}",
            flush=True,
        )
        if pending == 0:
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
            "tournament-details",
            "--limit",
            str(min(args.batch_size, pending)),
        ]
        result = subprocess.run(command, check=False)
        if result.returncode != 0:
            print(f"batch failed returncode={result.returncode}", flush=True)
        time.sleep(args.pause)


if __name__ == "__main__":
    raise SystemExit(main())
