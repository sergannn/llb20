#!/usr/bin/env python3
"""Run tournament detail and match scraping in resumable batches."""

from __future__ import annotations

import argparse
import signal
import sqlite3
import subprocess
import sys
import time
from pathlib import Path


def counts(db_path: Path) -> dict[str, int]:
    with sqlite3.connect(db_path) as conn:
        cur = conn.cursor()
        tables = {row[0] for row in cur.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        out = {
            "tournaments": cur.execute("SELECT count(*) FROM tournaments").fetchone()[0],
            "details": cur.execute(
                "SELECT count(*) FROM tournaments WHERE detail_fetched_at IS NOT NULL"
            ).fetchone()[0],
            "comps": cur.execute("SELECT count(*) FROM tournaments WHERE comp_id IS NOT NULL").fetchone()[0],
            "matches": cur.execute("SELECT count(*) FROM matches").fetchone()[0],
            "participants": cur.execute("SELECT count(*) FROM tournament_participants").fetchone()[0],
        }
        if "tournament_match_fetches" in tables:
            out["match_fetches"] = cur.execute(
                "SELECT count(*) FROM tournament_match_fetches"
            ).fetchone()[0]
        else:
            out["match_fetches"] = 0
        return {key: int(value) for key, value in out.items()}


def run(command: list[str]) -> int:
    return subprocess.run(command, check=False, start_new_session=True).returncode


def main() -> int:
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, signal.SIG_IGN)

    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--cookies", required=True)
    parser.add_argument("--sleep", default="1.5")
    parser.add_argument("--detail-batch-size", type=int, default=25)
    parser.add_argument("--match-batch-size", type=int, default=10)
    parser.add_argument("--pause", type=float, default=5)
    args = parser.parse_args()

    db_path = Path(args.db)
    scraper = Path(__file__).with_name("llb_scraper.py")

    while True:
        current = counts(db_path)
        detail_remaining = current["tournaments"] - current["details"]
        match_remaining = current["comps"] - current["match_fetches"]
        print(
            "tournament batch status "
            f"details={current['details']}/{current['tournaments']} "
            f"comps={current['comps']} "
            f"match_fetches={current['match_fetches']} "
            f"matches={current['matches']} "
            f"participants={current['participants']} "
            f"detail_remaining={detail_remaining} "
            f"match_remaining={match_remaining}",
            flush=True,
        )
        if detail_remaining > 0:
            code = run(
                [
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
                    str(min(args.detail_batch_size, detail_remaining)),
                ]
            )
        elif match_remaining > 0:
            code = run(
                [
                    sys.executable,
                    str(scraper),
                    "--cookies",
                    args.cookies,
                    "--sleep",
                    args.sleep,
                    "--db",
                    str(db_path),
                    "matches",
                    "--limit-competitions",
                    str(min(args.match_batch_size, match_remaining)),
                ]
            )
        else:
            return 0

        if code != 0:
            print(f"tournament batch failed returncode={code}", flush=True)
        time.sleep(args.pause)


if __name__ == "__main__":
    raise SystemExit(main())
