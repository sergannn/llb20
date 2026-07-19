#!/usr/bin/env python3
"""Import LLB SQLite shards into MySQL using the mysql command-line client."""

from __future__ import annotations

import argparse
import os
import sqlite3
import subprocess
from pathlib import Path
from typing import Iterable


TABLE_KEYS = {
    "players": ["id"],
    "player_ratings": ["player_id", "rating_key"],
    "player_tournament_entries": ["player_id", "tournament_id", "membership_node_id"],
    "tournaments": ["id"],
    "tournament_stages": ["comp_id", "stage_id"],
    "tournament_participants": ["comp_id", "stage_id", "player_id"],
    "archive_tournament_participants": ["tournament_id", "membership_node_id", "name"],
    "archive_tournament_fetches": ["tournament_id"],
    "matches": ["comp_id", "stage_id", "game_no"],
    "player_rating_events": ["player_id", "comp_id", "stage_id", "game_no", "side"],
}

TABLES = list(TABLE_KEYS)

PRESERVE_EXISTING_WHEN_NULL = {
    "players": {
        "birthday",
        "country",
        "country_id",
        "city",
        "registered_at",
        "source_page",
        "elo",
        "rating_text",
        "detail_json",
        "detail_fetched_at",
        "avatar_url",
        "contacts_raw",
        "phone",
        "email",
        "telegram",
        "whatsapp",
    },
    "tournaments": {"club_id", "participants_count", "participants_limit", "comp_id", "detail_json", "detail_fetched_at"},
}


INTEGER_COLUMNS = {
    "players": {"id", "country_id", "source_page", "elo"},
    "player_ratings": {"player_id", "elo", "comps_year", "comps_total"},
    "player_tournament_entries": {
        "player_id",
        "membership_node_id",
        "tournament_id",
        "source_page",
    },
    "tournaments": {"id", "club_id", "participants_count", "participants_limit", "comp_id", "source_page"},
    "tournament_stages": {"comp_id", "stage_id", "tournament_id"},
    "tournament_participants": {"comp_id", "stage_id", "player_id", "seed", "birth_year", "place"},
    "archive_tournament_participants": {"tournament_id", "membership_node_id", "seed"},
    "archive_tournament_fetches": {"tournament_id", "rows_count"},
    "matches": {
        "comp_id",
        "stage_id",
        "game_no",
        "tournament_id",
        "player1_id",
        "player1_elo_before",
        "player1_elo_after",
        "player2_id",
        "player2_elo_before",
        "player2_elo_after",
        "score1",
        "score2",
        "table_no",
    },
    "player_rating_events": {"player_id", "comp_id", "stage_id", "game_no", "elo_before", "elo_after"},
}


def mysql_literal(table: str, column: str, value: object) -> str:
    if value is None:
        return "NULL"
    if column in INTEGER_COLUMNS.get(table, set()) and value == "":
        return "NULL"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    return "'" + text.replace("\\", "\\\\").replace("'", "\\'").replace("\0", "") + "'"


def chunks(values: list[sqlite3.Row], size: int) -> Iterable[list[sqlite3.Row]]:
    for index in range(0, len(values), size):
        yield values[index : index + size]


def table_columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [row[1] for row in conn.execute(f"PRAGMA table_info({table})")]


def table_exists(conn: sqlite3.Connection, table: str) -> bool:
    row = conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone()
    return bool(row)


def build_insert(table: str, columns: list[str], rows: list[sqlite3.Row]) -> str:
    quoted_columns = ", ".join(f"`{column}`" for column in columns)
    values = []
    for row in rows:
        values.append("(" + ", ".join(mysql_literal(table, column, row[column]) for column in columns) + ")")
    key_columns = set(TABLE_KEYS[table])
    updates = []
    preserve_columns = PRESERVE_EXISTING_WHEN_NULL.get(table, set())
    for column in columns:
        if column in key_columns:
            continue
        if column in preserve_columns:
            updates.append(f"`{column}`=COALESCE(VALUES(`{column}`), `{column}`)")
        else:
            updates.append(f"`{column}`=VALUES(`{column}`)")
    return (
        f"INSERT INTO `{table}` ({quoted_columns}) VALUES\n"
        + ",\n".join(values)
        + "\nON DUPLICATE KEY UPDATE "
        + ", ".join(updates)
        + ";\n"
    )


def mysql_base_cmd(args: argparse.Namespace) -> list[str]:
    cmd = ["mysql"]
    cmd.append("--default-character-set=utf8mb4")
    if args.host:
        cmd.extend(["-h", args.host])
    if args.port:
        cmd.extend(["-P", str(args.port)])
    if args.user:
        cmd.extend(["-u", args.user])
    if args.password:
        cmd.append(f"-p{args.password}")
    cmd.append(args.database)
    return cmd


def run_mysql(args: argparse.Namespace, sql: str) -> None:
    try:
        subprocess.run(mysql_base_cmd(args), input=sql.encode("utf-8"), check=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"mysql import failed with exit code {exc.returncode}") from None


def sqlite_comp_ids(conn: sqlite3.Connection) -> list[int]:
    comp_ids: set[int] = set()
    for table in ("tournament_stages", "tournament_participants", "matches", "player_rating_events"):
        if not table_exists(conn, table):
            continue
        for row in conn.execute(f"SELECT DISTINCT comp_id FROM {table} WHERE comp_id IS NOT NULL"):
            comp_ids.add(int(row["comp_id"]))
    return sorted(comp_ids)


def replace_competition_data(args: argparse.Namespace, conn: sqlite3.Connection) -> None:
    comp_ids = sqlite_comp_ids(conn)
    if not comp_ids:
        return
    tables = ("player_rating_events", "matches", "tournament_participants", "tournament_stages")
    for id_chunk in chunks(comp_ids, args.batch_size):
        ids_sql = ", ".join(str(int(comp_id)) for comp_id in id_chunk)
        sql = "".join(f"DELETE FROM `{table}` WHERE comp_id IN ({ids_sql});\n" for table in tables)
        run_mysql(args, sql)
    print(f"replaced competition rows for {len(comp_ids)} comp ids", flush=True)


def import_one(args: argparse.Namespace, sqlite_path: Path) -> None:
    conn = sqlite3.connect(sqlite_path)
    conn.row_factory = sqlite3.Row
    try:
        if args.replace_competition_data:
            replace_competition_data(args, conn)
        for table in TABLES:
            if not table_exists(conn, table):
                continue
            columns = table_columns(conn, table)
            if not columns:
                continue
            order_by = ", ".join(TABLE_KEYS[table])
            rows: list[sqlite3.Row] = []
            total = 0
            for row in conn.execute(f"SELECT {', '.join(columns)} FROM {table} ORDER BY {order_by}"):
                if table == "tournament_participants" and row["player_id"] is None:
                    continue
                rows.append(row)
                if len(rows) >= args.batch_size:
                    run_mysql(args, build_insert(table, columns, rows))
                    total += len(rows)
                    rows = []
            if rows:
                run_mysql(args, build_insert(table, columns, rows))
                total += len(rows)
            print(f"{sqlite_path.name}: {table} {total}", flush=True)
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Import SQLite shards into MySQL.")
    parser.add_argument("sqlite", nargs="+", type=Path)
    parser.add_argument("--database", default=os.getenv("LLB_MYSQL_DATABASE", "llb_mobile"))
    parser.add_argument("--host", default=os.getenv("LLB_MYSQL_HOST", "localhost"))
    parser.add_argument("--port", type=int, default=int(os.getenv("LLB_MYSQL_PORT", "3306")))
    parser.add_argument("--user", default=os.getenv("LLB_MYSQL_USER"))
    parser.add_argument("--password", default=os.getenv("LLB_MYSQL_PASSWORD"))
    parser.add_argument("--batch-size", type=int, default=500)
    parser.add_argument(
        "--replace-competition-data",
        action="store_true",
        help="Delete MySQL stages, participants, matches and rating events for comp ids present in SQLite before importing them.",
    )
    args = parser.parse_args()
    for path in args.sqlite:
        import_one(args, path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
