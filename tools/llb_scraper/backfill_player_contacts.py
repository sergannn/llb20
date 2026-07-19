#!/usr/bin/env python3
"""Normalize player contacts from detail_json into dedicated SQLite columns."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

from llb_scraper import Database, extract_contact_fields, now_iso


def main() -> int:
    parser = argparse.ArgumentParser(description="Backfill player contact columns from detail_json.")
    parser.add_argument("--db", type=Path, default=Path("data/llb.sqlite3"))
    args = parser.parse_args()

    db = Database(args.db)
    rows = db.conn.execute(
        """
        SELECT id, detail_json
        FROM players
        WHERE detail_json IS NOT NULL AND detail_json <> ''
        """
    ).fetchall()
    changed = 0
    with_contacts = 0
    with_phone = 0
    for row in rows:
        try:
            detail = json.loads(row["detail_json"])
        except json.JSONDecodeError:
            continue
        if not isinstance(detail, dict):
            continue
        contacts = extract_contact_fields(detail)
        if contacts["contacts_raw"]:
            with_contacts += 1
        if contacts["phone"]:
            with_phone += 1
        db.conn.execute(
            """
            UPDATE players
            SET contacts_raw=?, phone=?, email=?, telegram=?, whatsapp=?, updated_at=?
            WHERE id=?
            """,
            (
                contacts["contacts_raw"],
                contacts["phone"],
                contacts["email"],
                contacts["telegram"],
                contacts["whatsapp"],
                now_iso(),
                row["id"],
            ),
        )
        changed += 1
    db.conn.commit()
    print(f"processed={changed} contacts={with_contacts} phones={with_phone}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
