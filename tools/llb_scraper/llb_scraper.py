#!/usr/bin/env python3
"""Import public LLB players, tournaments, participants and matches into SQLite.

The scraper uses only Python's standard library. Credentials are optional for
most public pages, but player detail pages may show extra fields after login.
"""

from __future__ import annotations

import argparse
import dataclasses
import html
import http.cookiejar
import json
import os
import re
import socket
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path


WWW_BASE = "https://www.llb.su"
TOURNAMENT_BASE = "https://t.llb.su"
USER_AGENT = "Mozilla/5.0 (compatible; llb-mobile-importer/0.1)"


class HttpStatusError(RuntimeError):
    def __init__(self, code: int, url: str, body: bytes):
        self.code = code
        self.url = url
        self.body = body
        super().__init__(f"HTTP {code} for {url}: {body[:200]!r}")


def install_host_overrides(value: str | None) -> None:
    if not value:
        return
    overrides: dict[str, str] = {}
    for item in re.split(r"[,;]\s*", value):
        if not item or "=" not in item:
            continue
        host, ip = item.split("=", 1)
        host = host.strip().lower()
        ip = ip.strip()
        if host and ip:
            overrides[host] = ip
    if not overrides:
        return
    original_getaddrinfo = socket.getaddrinfo

    def getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
        replacement = overrides.get(str(host).lower())
        return original_getaddrinfo(replacement or host, port, family, type, proto, flags)

    socket.getaddrinfo = getaddrinfo


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def clean_text(value: str | None) -> str:
    if not value:
        return ""
    text = html.unescape(value)
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?is)<script.*?</script>|<style.*?</style>", " ", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = text.replace("\xa0", " ")
    text = re.sub(r"[ \t\r\f\v]+", " ", text)
    text = re.sub(r"\n\s+", "\n", text)
    return text.strip()


def to_int(value: str | None) -> int | None:
    if value is None:
        return None
    match = re.search(r"\d+", value.replace(" ", ""))
    return int(match.group(0)) if match else None


def absolute_url(base: str, url: str) -> str:
    if url.startswith("//"):
        return "https:" + url
    return urllib.parse.urljoin(base, url)


def first_image_url(fragment: str, base: str = WWW_BASE) -> str | None:
    match = re.search(r"(?is)<img\b[^>]*\bsrc=[\"']([^\"']+)[\"'][^>]*\bclass=[\"'][^\"']*photo[^\"']*[\"']", fragment)
    if not match:
        match = re.search(r"(?is)<img\b[^>]*\bclass=[\"'][^\"']*photo[^\"']*[\"'][^>]*\bsrc=[\"']([^\"']+)[\"']", fragment)
    return absolute_url(base, html.unescape(match.group(1))) if match else None


class HttpClient:
    def __init__(
        self,
        username: str | None = None,
        password: str | None = None,
        sleep: float = 0.25,
        cookie_file: Path | None = None,
    ):
        self.username = username
        self.password = password
        self.sleep = sleep
        self.cookie_file = cookie_file
        self.cookie_jar = http.cookiejar.MozillaCookieJar(str(cookie_file)) if cookie_file else http.cookiejar.CookieJar()
        self.load_cookies()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookie_jar))
        self.last_request_at = 0.0
        self.logged_in = False

    def load_cookies(self) -> None:
        if not self.cookie_file or not self.cookie_file.exists():
            return
        try:
            self.cookie_jar.load(ignore_discard=True, ignore_expires=True)
        except (OSError, http.cookiejar.LoadError):
            return

    def save_cookies(self) -> None:
        if not self.cookie_file or not hasattr(self.cookie_jar, "save"):
            return
        self.cookie_file.parent.mkdir(parents=True, exist_ok=True)
        self.cookie_jar.save(ignore_discard=True, ignore_expires=True)

    def session_valid(self) -> bool:
        page = self.request("/")
        self.logged_in = "not-logged-in" not in page and ("Выйти" in page or "/logout" in page or "/user/logout" in page)
        return self.logged_in

    def throttle(self) -> None:
        elapsed = time.monotonic() - self.last_request_at
        if elapsed < self.sleep:
            time.sleep(self.sleep - elapsed)

    def request(self, url: str, data: dict[str, str] | None = None, base: str = WWW_BASE) -> str:
        self.throttle()
        full_url = absolute_url(base, url)
        body = None
        if data is not None:
            body = urllib.parse.urlencode(data).encode("utf-8")
        request = urllib.request.Request(
            full_url,
            data=body,
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            },
        )
        attempts = 3
        for attempt in range(1, attempts + 1):
            try:
                with self.opener.open(request, timeout=45) as response:
                    raw = response.read()
                break
            except urllib.error.HTTPError as exc:
                raw = exc.read()
                raise HttpStatusError(exc.code, full_url, raw) from exc
            except (urllib.error.URLError, TimeoutError, socket.timeout, ConnectionError):
                if attempt == attempts:
                    raise
                time.sleep(max(self.sleep, 1.0) * attempt)
            finally:
                self.last_request_at = time.monotonic()
        return raw.decode("utf-8", errors="replace")

    def login(self) -> bool:
        if self.session_valid():
            return True
        if not self.username or not self.password:
            return False
        self.request("/user/login")
        page = self.request(
            "/user/login?destination=login_redirect",
            data={
                "name": self.username,
                "pass": self.password,
                "form_id": "user_login",
                "op": "Войти!",
            },
        )
        self.logged_in = "not-logged-in" not in page and "/user/logout" in page
        if not self.logged_in:
            account = self.request("/")
            self.logged_in = "not-logged-in" not in account and (
                self.username.lower() in account.lower() or "/user/logout" in account
            )
        if self.logged_in:
            self.save_cookies()
        return self.logged_in

    def ensure_login(self) -> bool:
        if self.session_valid():
            return True
        return self.login()


class TableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rows: list[list[dict[str, object]]] = []
        self.current_row: list[dict[str, object]] | None = None
        self.current_cell: dict[str, object] | None = None
        self.cell_depth = 0
        self.active_link_index: int | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = {key: value or "" for key, value in attrs}
        if tag == "tr":
            self.current_row = []
        elif tag in {"td", "th"} and self.current_row is not None:
            self.current_cell = {"text": "", "html": "", "links": [], "attrs": attrs_dict}
            self.cell_depth = 1
        elif self.current_cell is not None:
            self.cell_depth += 1
            self.current_cell["html"] = str(self.current_cell["html"]) + self.get_starttag_text()
            if tag == "a":
                links = self.current_cell["links"]
                assert isinstance(links, list)
                links.append({"href": attrs_dict.get("href", ""), "text": ""})
                self.active_link_index = len(links) - 1

    def handle_endtag(self, tag: str) -> None:
        if self.current_cell is not None:
            if tag == "a":
                self.current_cell["html"] = str(self.current_cell["html"]) + f"</{tag}>"
                self.active_link_index = None
            if tag in {"td", "th"} and self.cell_depth == 1:
                self.current_row.append(self.current_cell)
                self.current_cell = None
                self.cell_depth = 0
                self.active_link_index = None
                return
            self.cell_depth = max(0, self.cell_depth - 1)
        if tag == "tr" and self.current_row is not None:
            if self.current_row:
                self.rows.append(self.current_row)
            self.current_row = None

    def handle_data(self, data: str) -> None:
        if self.current_cell is None:
            return
        self.current_cell["text"] = str(self.current_cell["text"]) + data
        self.current_cell["html"] = str(self.current_cell["html"]) + html.escape(data)
        links = self.current_cell["links"]
        if isinstance(links, list) and self.active_link_index is not None and len(links) > self.active_link_index:
            links[self.active_link_index]["text"] = str(links[self.active_link_index]["text"]) + data


def first_table_rows(page: str, table_id: str | None = None, content_class: str | None = None) -> list[list[dict[str, object]]]:
    fragment = page
    if table_id:
        match = re.search(rf"(?is)<table\b[^>]*\bid=['\"]{re.escape(table_id)}['\"][^>]*>.*?</table>", page)
        fragment = match.group(0) if match else ""
    elif content_class:
        match = re.search(rf"(?is)<div class=['\"][^'\"]*{re.escape(content_class)}[^'\"]*['\"][^>]*>.*?</table>", page)
        fragment = match.group(0) if match else ""
    parser = TableParser()
    parser.feed(fragment)
    return parser.rows


def max_page(page: str, default: int = 0) -> int:
    pages = [int(item) for item in re.findall(r"[?&]page=(\d+)", page)]
    return max(pages) if pages else default


@dataclasses.dataclass
class PlayerRow:
    player_id: int
    name: str
    href: str
    birthday: str
    country: str
    country_id: int | None
    city: str
    registered_at: str
    source_page: int


@dataclasses.dataclass
class TournamentRow:
    tournament_id: int
    title: str
    href: str
    source_kind: str
    status_class: str
    date_text: str
    club: str
    club_id: int | None
    participants_count: int | None
    participants_limit: int | None
    source_page: int


@dataclasses.dataclass
class PlayerTournamentEntry:
    player_id: int
    membership_node_id: int | None
    tournament_id: int
    title: str
    date_text: str
    points: str
    place: str
    source_page: int


@dataclasses.dataclass
class ArchiveTournamentParticipant:
    tournament_id: int
    membership_node_id: int | None
    seed: int | None
    name: str
    level: str
    points: str
    place: str


class Database:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(path)
        self.conn.row_factory = sqlite3.Row
        self.init_schema()

    def init_schema(self) -> None:
        self.conn.executescript(
            """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS players (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                href TEXT NOT NULL,
                birthday TEXT,
                country TEXT,
                country_id INTEGER,
                city TEXT,
                registered_at TEXT,
                avatar_url TEXT,
                source_page INTEGER,
                elo INTEGER,
                rating_text TEXT,
                detail_json TEXT,
                detail_fetched_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS tournaments (
                id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                href TEXT NOT NULL,
                source_kind TEXT,
                status_class TEXT,
                date_text TEXT,
                club TEXT,
                club_id INTEGER,
                participants_count INTEGER,
                participants_limit INTEGER,
                comp_id INTEGER,
                detail_json TEXT,
                detail_fetched_at TEXT,
                source_page INTEGER,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS tournament_stages (
                comp_id INTEGER NOT NULL,
                stage_id INTEGER NOT NULL,
                tournament_id INTEGER,
                name TEXT,
                fetched_at TEXT,
                PRIMARY KEY (comp_id, stage_id)
            );
            CREATE TABLE IF NOT EXISTS tournament_participants (
                comp_id INTEGER NOT NULL,
                stage_id INTEGER NOT NULL,
                player_id INTEGER,
                seed INTEGER,
                name TEXT NOT NULL,
                birth_year TEXT,
                rank TEXT,
                country TEXT,
                city TEXT,
                place TEXT,
                avatar_url TEXT,
                fetched_at TEXT NOT NULL,
                PRIMARY KEY (comp_id, stage_id, player_id, name)
            );
            CREATE TABLE IF NOT EXISTS archive_tournament_participants (
                tournament_id INTEGER NOT NULL,
                membership_node_id INTEGER NOT NULL DEFAULT 0,
                seed INTEGER,
                name TEXT NOT NULL,
                level TEXT,
                points TEXT,
                place TEXT,
                fetched_at TEXT NOT NULL,
                PRIMARY KEY (tournament_id, membership_node_id, name)
            );
            CREATE TABLE IF NOT EXISTS archive_tournament_fetches (
                tournament_id INTEGER PRIMARY KEY,
                status TEXT NOT NULL,
                rows_count INTEGER NOT NULL DEFAULT 0,
                fetched_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS matches (
                comp_id INTEGER NOT NULL,
                stage_id INTEGER NOT NULL,
                game_no INTEGER NOT NULL,
                tournament_id INTEGER,
                round_name TEXT,
                status_class TEXT,
                player1_id INTEGER,
                player1_name TEXT,
                player1_elo_before INTEGER,
                player1_elo_after INTEGER,
                player2_id INTEGER,
                player2_name TEXT,
                player2_elo_before INTEGER,
                player2_elo_after INTEGER,
                score1 TEXT,
                score2 TEXT,
                params TEXT,
                table_no TEXT,
                planned_at TEXT,
                started_at TEXT,
                finished_at TEXT,
                video TEXT,
                raw_json TEXT,
                fetched_at TEXT NOT NULL,
                PRIMARY KEY (comp_id, stage_id, game_no)
            );
            CREATE TABLE IF NOT EXISTS import_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS player_rating_events (
                player_id INTEGER NOT NULL,
                comp_id INTEGER NOT NULL,
                stage_id INTEGER NOT NULL,
                game_no INTEGER NOT NULL,
                side INTEGER NOT NULL,
                player_name TEXT,
                elo_before INTEGER,
                elo_after INTEGER,
                fetched_at TEXT NOT NULL,
                PRIMARY KEY (player_id, comp_id, stage_id, game_no, side)
            );
            CREATE TABLE IF NOT EXISTS player_ratings (
                player_id INTEGER NOT NULL,
                rating_key TEXT NOT NULL,
                discipline TEXT,
                rating_label TEXT,
                elo INTEGER,
                comps_year INTEGER,
                comps_total INTEGER,
                source TEXT NOT NULL,
                fetched_at TEXT NOT NULL,
                PRIMARY KEY (player_id, rating_key)
            );
            CREATE TABLE IF NOT EXISTS player_tournament_entries (
                player_id INTEGER NOT NULL,
                membership_node_id INTEGER NOT NULL DEFAULT 0,
                tournament_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                date_text TEXT,
                points TEXT,
                place TEXT,
                source_page INTEGER,
                fetched_at TEXT NOT NULL,
                PRIMARY KEY (player_id, tournament_id, membership_node_id)
            );
            CREATE TABLE IF NOT EXISTS tournament_match_fetches (
                comp_id INTEGER PRIMARY KEY,
                tournament_id INTEGER,
                fetched_at TEXT NOT NULL
            );
            """
        )
        self.ensure_column("matches", "player1_elo_before", "INTEGER")
        self.ensure_column("matches", "player1_elo_after", "INTEGER")
        self.ensure_column("matches", "player2_elo_before", "INTEGER")
        self.ensure_column("matches", "player2_elo_after", "INTEGER")
        self.ensure_column("players", "avatar_url", "TEXT")
        self.ensure_column("players", "contacts_raw", "TEXT")
        self.ensure_column("players", "phone", "TEXT")
        self.ensure_column("players", "email", "TEXT")
        self.ensure_column("players", "telegram", "TEXT")
        self.ensure_column("players", "whatsapp", "TEXT")
        self.ensure_column("tournament_participants", "avatar_url", "TEXT")
        self.conn.commit()

    def ensure_column(self, table: str, column: str, column_type: str) -> None:
        existing = {row[1] for row in self.conn.execute(f"PRAGMA table_info({table})")}
        if column not in existing:
            self.conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {column_type}")

    def upsert_player(self, row: PlayerRow) -> None:
        stamp = now_iso()
        self.conn.execute(
            """
            INSERT INTO players (
                id, name, href, birthday, country, country_id, city, registered_at,
                source_page, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name=excluded.name, href=excluded.href, birthday=excluded.birthday,
                country=excluded.country, country_id=excluded.country_id,
                city=excluded.city, registered_at=excluded.registered_at,
                source_page=excluded.source_page, updated_at=excluded.updated_at
            """,
            (
                row.player_id,
                row.name,
                row.href,
                row.birthday,
                row.country,
                row.country_id,
                row.city,
                row.registered_at,
                row.source_page,
                stamp,
                stamp,
            ),
        )
    def upsert_rating_event(self, comp_id: int, stage_id: int, item: dict[str, object], side: int) -> None:
        player_id = item.get(f"player{side}_id")
        elo_before = item.get(f"player{side}_elo_before")
        elo_after = item.get(f"player{side}_elo_after")
        if not player_id or elo_before is None or elo_after is None:
            return
        name = item.get(f"player{side}_name")
        game_no = item["game_no"]
        stamp = now_iso()
        self.conn.execute(
            """
            INSERT OR REPLACE INTO player_rating_events (
                player_id, comp_id, stage_id, game_no, side, player_name, elo_before, elo_after, fetched_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (player_id, comp_id, stage_id, game_no, side, name, elo_before, elo_after, stamp),
        )
        self.conn.execute(
            """
            INSERT INTO players (id, name, href, elo, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                elo=COALESCE(players.elo, excluded.elo),
                name=CASE WHEN players.name='' OR players.name IS NULL THEN excluded.name ELSE players.name END,
                updated_at=excluded.updated_at
            """,
            (player_id, name or "", f"/node/{player_id}", elo_after, stamp, stamp),
        )

    def upsert_player_detail(
        self,
        player_id: int,
        detail: dict[str, object],
        elo: int | None,
        rating_text: str | None,
        ratings: list[dict[str, object]],
    ) -> None:
        avatar_url = detail.get("avatar_url")
        contacts = extract_contact_fields(detail)
        self.conn.execute(
            """
            UPDATE players
            SET detail_json=?, elo=COALESCE(?, elo), rating_text=?,
                name=CASE
                    WHEN COALESCE(json_extract(?, '$.name'), '') <> ''
                         AND (
                             players.name IS NULL OR players.name = ''
                             OR length(json_extract(?, '$.name')) > length(players.name)
                         )
                    THEN json_extract(?, '$.name')
                    ELSE players.name
                END,
                avatar_url=COALESCE(?, avatar_url),
                contacts_raw=COALESCE(NULLIF(?, ''), contacts_raw),
                phone=COALESCE(NULLIF(?, ''), phone),
                email=COALESCE(NULLIF(?, ''), email),
                telegram=COALESCE(NULLIF(?, ''), telegram),
                whatsapp=COALESCE(NULLIF(?, ''), whatsapp),
                detail_fetched_at=?, updated_at=?
            WHERE id=?
            """,
            (
                json.dumps(detail, ensure_ascii=False, sort_keys=True),
                elo,
                rating_text,
                json.dumps(detail, ensure_ascii=False, sort_keys=True),
                json.dumps(detail, ensure_ascii=False, sort_keys=True),
                json.dumps(detail, ensure_ascii=False, sort_keys=True),
                avatar_url,
                contacts["contacts_raw"],
                contacts["phone"],
                contacts["email"],
                contacts["telegram"],
                contacts["whatsapp"],
                now_iso(),
                now_iso(),
                player_id,
            ),
        )
        for rating in ratings:
            self.upsert_player_rating(player_id, rating)

    def upsert_player_rating(self, player_id: int, rating: dict[str, object]) -> None:
        self.conn.execute(
            """
            INSERT INTO player_ratings (
                player_id, rating_key, discipline, rating_label, elo,
                comps_year, comps_total, source, fetched_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(player_id, rating_key) DO UPDATE SET
                discipline=excluded.discipline,
                rating_label=excluded.rating_label,
                elo=excluded.elo,
                comps_year=excluded.comps_year,
                comps_total=excluded.comps_total,
                source=excluded.source,
                fetched_at=excluded.fetched_at
            """,
            (
                player_id,
                rating.get("rating_key"),
                rating.get("discipline"),
                rating.get("rating_label"),
                rating.get("elo"),
                rating.get("comps_year"),
                rating.get("comps_total"),
                rating.get("source", "player_detail"),
                now_iso(),
            ),
        )

    def replace_player_tournament_entries(self, player_id: int, entries: list[PlayerTournamentEntry]) -> None:
        self.conn.execute("DELETE FROM player_tournament_entries WHERE player_id=?", (player_id,))
        for entry in entries:
            self.conn.execute(
                """
                INSERT INTO player_tournament_entries (
                    player_id, membership_node_id, tournament_id, title, date_text,
                    points, place, source_page, fetched_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(player_id, tournament_id, membership_node_id) DO UPDATE SET
                    title=excluded.title,
                    date_text=excluded.date_text,
                    points=excluded.points,
                    place=excluded.place,
                    source_page=excluded.source_page,
                    fetched_at=excluded.fetched_at
                """,
                (
                    entry.player_id,
                    entry.membership_node_id or 0,
                    entry.tournament_id,
                    entry.title,
                    entry.date_text,
                    entry.points,
                    entry.place,
                    entry.source_page,
                    now_iso(),
                ),
            )

    def upsert_tournament(self, row: TournamentRow) -> None:
        stamp = now_iso()
        self.conn.execute(
            """
            INSERT INTO tournaments (
                id, title, href, source_kind, status_class, date_text, club, club_id,
                participants_count, participants_limit, source_page, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title=excluded.title, href=excluded.href, source_kind=excluded.source_kind,
                status_class=excluded.status_class, date_text=excluded.date_text,
                club=excluded.club, club_id=excluded.club_id,
                participants_count=excluded.participants_count,
                participants_limit=excluded.participants_limit,
                source_page=excluded.source_page, updated_at=excluded.updated_at
            """,
            (
                row.tournament_id,
                row.title,
                row.href,
                row.source_kind,
                row.status_class,
                row.date_text,
                row.club,
                row.club_id,
                row.participants_count,
                row.participants_limit,
                row.source_page,
                stamp,
                stamp,
            ),
        )

    def upsert_tournament_detail(self, tournament_id: int, detail: dict[str, object], comp_id: int | None) -> None:
        self.conn.execute(
            """
            UPDATE tournaments
            SET comp_id=?, detail_json=?, detail_fetched_at=?, updated_at=?
            WHERE id=?
            """,
            (comp_id, json.dumps(detail, ensure_ascii=False, sort_keys=True), now_iso(), now_iso(), tournament_id),
        )

    def upsert_archive_tournament_shell(self, tournament_id: int, title: str) -> None:
        stamp = now_iso()
        self.conn.execute(
            """
            INSERT INTO tournaments (
                id, title, href, source_kind, status_class, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title=CASE
                    WHEN tournaments.title='' OR tournaments.title IS NULL THEN excluded.title
                    ELSE tournaments.title
                END,
                href=CASE
                    WHEN tournaments.href='' OR tournaments.href IS NULL THEN excluded.href
                    ELSE tournaments.href
                END,
                source_kind=COALESCE(tournaments.source_kind, excluded.source_kind),
                updated_at=excluded.updated_at
            """,
            (tournament_id, title or f"Турнир {tournament_id}", f"/node/{tournament_id}", "archive", "archive", stamp, stamp),
        )

    def replace_archive_tournament_participants(
        self,
        tournament_id: int,
        participants: list[ArchiveTournamentParticipant],
    ) -> None:
        self.conn.execute("DELETE FROM archive_tournament_participants WHERE tournament_id=?", (tournament_id,))
        for item in participants:
            self.conn.execute(
                """
                INSERT INTO archive_tournament_participants (
                    tournament_id, membership_node_id, seed, name, level, points, place, fetched_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(tournament_id, membership_node_id, name) DO UPDATE SET
                    seed=excluded.seed,
                    level=excluded.level,
                    points=excluded.points,
                    place=excluded.place,
                    fetched_at=excluded.fetched_at
                """,
                (
                    item.tournament_id,
                    item.membership_node_id or 0,
                    item.seed,
                    item.name,
                    item.level,
                    item.points,
                    item.place,
                    now_iso(),
                ),
            )

    def mark_archive_tournament_fetched(self, tournament_id: int, status: str, rows_count: int) -> None:
        self.conn.execute(
            """
            INSERT INTO archive_tournament_fetches (tournament_id, status, rows_count, fetched_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(tournament_id) DO UPDATE SET
                status=excluded.status,
                rows_count=excluded.rows_count,
                fetched_at=excluded.fetched_at
            """,
            (tournament_id, status, rows_count, now_iso()),
        )

    def upsert_stage(self, comp_id: int, stage_id: int, tournament_id: int | None, name: str) -> None:
        self.conn.execute(
            """
            INSERT INTO tournament_stages (comp_id, stage_id, tournament_id, name, fetched_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(comp_id, stage_id) DO UPDATE SET
                tournament_id=excluded.tournament_id, name=excluded.name, fetched_at=excluded.fetched_at
            """,
            (comp_id, stage_id, tournament_id, name, now_iso()),
        )

    def upsert_participant(self, comp_id: int, stage_id: int, item: dict[str, object]) -> None:
        self.conn.execute(
            """
            INSERT OR REPLACE INTO tournament_participants (
                comp_id, stage_id, player_id, seed, name, birth_year, rank, country, city, place, avatar_url, fetched_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                comp_id,
                stage_id,
                item.get("player_id"),
                item.get("seed"),
                item.get("name"),
                item.get("birth_year"),
                item.get("rank"),
                item.get("country"),
                item.get("city"),
                item.get("place"),
                item.get("avatar_url"),
                now_iso(),
            ),
        )
        if item.get("player_id") and item.get("avatar_url"):
            stamp = now_iso()
            self.conn.execute(
                """
                INSERT INTO players (id, name, href, avatar_url, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    avatar_url=COALESCE(players.avatar_url, excluded.avatar_url),
                    name=CASE WHEN players.name='' OR players.name IS NULL THEN excluded.name ELSE players.name END,
                    updated_at=excluded.updated_at
                """,
                (
                    item.get("player_id"),
                    item.get("name") or "",
                    f"/node/{item.get('player_id')}",
                    item.get("avatar_url"),
                    stamp,
                    stamp,
                ),
            )

    def upsert_match(self, comp_id: int, stage_id: int, tournament_id: int | None, item: dict[str, object]) -> None:
        self.conn.execute(
            """
            INSERT OR REPLACE INTO matches (
                comp_id, stage_id, game_no, tournament_id, round_name, status_class,
                player1_id, player1_name, player1_elo_before, player1_elo_after,
                player2_id, player2_name, player2_elo_before, player2_elo_after, score1, score2,
                params, table_no, planned_at, started_at, finished_at, video, raw_json, fetched_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                comp_id,
                stage_id,
                item["game_no"],
                tournament_id,
                item.get("round_name"),
                item.get("status_class"),
                item.get("player1_id"),
                item.get("player1_name"),
                item.get("player1_elo_before"),
                item.get("player1_elo_after"),
                item.get("player2_id"),
                item.get("player2_name"),
                item.get("player2_elo_before"),
                item.get("player2_elo_after"),
                item.get("score1"),
                item.get("score2"),
                item.get("params"),
                item.get("table_no"),
                item.get("planned_at"),
                item.get("started_at"),
                item.get("finished_at"),
                item.get("video"),
                json.dumps(item, ensure_ascii=False, sort_keys=True),
                now_iso(),
            ),
        )
        self.upsert_rating_event(comp_id, stage_id, item, 1)
        self.upsert_rating_event(comp_id, stage_id, item, 2)

    def player_ids_for_details(self, limit: int | None, force: bool) -> list[int]:
        where = "" if force else "WHERE detail_fetched_at IS NULL"
        sql = f"SELECT id FROM players {where} ORDER BY id DESC"
        if limit:
            sql += f" LIMIT {int(limit)}"
        return [int(row["id"]) for row in self.conn.execute(sql)]

    def player_ids_for_tournament_entries(self, ids: list[int] | None, limit: int | None) -> list[int]:
        if ids:
            return ids
        sql = "SELECT id FROM players ORDER BY id DESC"
        if limit:
            sql += f" LIMIT {int(limit)}"
        return [int(row["id"]) for row in self.conn.execute(sql)]

    def tournament_ids_for_details(
        self,
        limit: int | None,
        force: bool,
        source_kinds: list[str] | None = None,
    ) -> list[int]:
        filters = []
        params: list[object] = []
        if not force:
            filters.append("detail_fetched_at IS NULL")
        if source_kinds:
            filters.append("source_kind IN (" + ", ".join("?" for _ in source_kinds) + ")")
            params.extend(source_kinds)
        where = "WHERE " + " AND ".join(filters) if filters else ""
        sql = f"SELECT id FROM tournaments {where} ORDER BY id DESC"
        if limit:
            sql += f" LIMIT {int(limit)}"
        return [int(row["id"]) for row in self.conn.execute(sql, params)]

    def competitions_for_matches(
        self,
        limit: int | None,
        force: bool = False,
        source_kinds: list[str] | None = None,
    ) -> list[sqlite3.Row]:
        filters = ["comp_id IS NOT NULL"]
        params: list[object] = []
        if not force:
            filters.append("comp_id NOT IN (SELECT comp_id FROM tournament_match_fetches)")
        if source_kinds:
            filters.append("source_kind IN (" + ", ".join("?" for _ in source_kinds) + ")")
            params.extend(source_kinds)
        sql = """
            SELECT id, comp_id
            FROM tournaments
            WHERE """ + " AND ".join(filters) + """
            ORDER BY id DESC
        """
        if limit:
            sql += f" LIMIT {int(limit)}"
        return list(self.conn.execute(sql, params))

    def archive_tournament_ids_for_participants(self, ids: list[int] | None, limit: int | None) -> list[int]:
        if ids:
            return ids
        sql = """
            SELECT DISTINCT e.tournament_id
            FROM player_tournament_entries e
            LEFT JOIN archive_tournament_participants a ON a.tournament_id = e.tournament_id
            LEFT JOIN archive_tournament_fetches f ON f.tournament_id = e.tournament_id
            WHERE e.tournament_id IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM tournaments t
                  WHERE t.id = e.tournament_id AND t.comp_id IS NOT NULL
              )
              AND a.tournament_id IS NULL
              AND f.tournament_id IS NULL
            ORDER BY e.tournament_id DESC
        """
        if limit:
            sql += f" LIMIT {int(limit)}"
        return [int(row["tournament_id"]) for row in self.conn.execute(sql)]

    def clear_competition_data(self, tournament_id: int, comp_id: int) -> None:
        self.conn.execute("DELETE FROM player_rating_events WHERE comp_id=?", (comp_id,))
        self.conn.execute("DELETE FROM matches WHERE comp_id=?", (comp_id,))
        self.conn.execute("DELETE FROM tournament_participants WHERE comp_id=?", (comp_id,))
        self.conn.execute("DELETE FROM tournament_stages WHERE comp_id=?", (comp_id,))
        self.conn.execute("DELETE FROM tournament_match_fetches WHERE comp_id=?", (comp_id,))
        self.conn.execute("UPDATE tournaments SET updated_at=? WHERE id=?", (now_iso(), tournament_id))

    def mark_competition_matches_fetched(self, tournament_id: int, comp_id: int) -> None:
        self.conn.execute(
            """
            INSERT INTO tournament_match_fetches (comp_id, tournament_id, fetched_at)
            VALUES (?, ?, ?)
            ON CONFLICT(comp_id) DO UPDATE SET
                tournament_id=excluded.tournament_id,
                fetched_at=excluded.fetched_at
            """,
            (comp_id, tournament_id, now_iso()),
        )

    def merge_from(self, shard_path: Path) -> dict[str, int]:
        before = self.counts()
        self.conn.execute("ATTACH DATABASE ? AS shard", (str(shard_path),))
        try:
            self.ensure_attached_column("shard", "players", "avatar_url", "TEXT")
            self.ensure_attached_column("shard", "players", "contacts_raw", "TEXT")
            self.ensure_attached_column("shard", "players", "phone", "TEXT")
            self.ensure_attached_column("shard", "players", "email", "TEXT")
            self.ensure_attached_column("shard", "players", "telegram", "TEXT")
            self.ensure_attached_column("shard", "players", "whatsapp", "TEXT")
            self.ensure_attached_column("shard", "tournament_participants", "avatar_url", "TEXT")
            self.ensure_attached_table_player_ratings("shard")
            self.ensure_attached_table_player_tournament_entries("shard")
            self.ensure_attached_table_archive_tournament_participants("shard")
            self.ensure_attached_table_archive_tournament_fetches("shard")
            self.conn.executescript(
                """
                INSERT INTO players (
                    id, name, href, birthday, country, country_id, city, registered_at,
                    source_page, elo, rating_text, detail_json, detail_fetched_at,
                    contacts_raw, phone, email, telegram, whatsapp,
                    created_at, updated_at, avatar_url
                )
                SELECT
                    id, name, href, birthday, country, country_id, city, registered_at,
                    source_page, elo, rating_text, detail_json, detail_fetched_at,
                    contacts_raw, phone, email, telegram, whatsapp,
                    created_at, updated_at, avatar_url
                FROM shard.players WHERE true
                ON CONFLICT(id) DO UPDATE SET
                    name=excluded.name,
                    href=excluded.href,
                    birthday=COALESCE(excluded.birthday, players.birthday),
                    country=COALESCE(excluded.country, players.country),
                    country_id=COALESCE(excluded.country_id, players.country_id),
                    city=COALESCE(excluded.city, players.city),
                    registered_at=COALESCE(excluded.registered_at, players.registered_at),
                    source_page=COALESCE(excluded.source_page, players.source_page),
                    avatar_url=COALESCE(excluded.avatar_url, players.avatar_url),
                    elo=COALESCE(excluded.elo, players.elo),
                    rating_text=COALESCE(excluded.rating_text, players.rating_text),
                    detail_json=COALESCE(excluded.detail_json, players.detail_json),
                    detail_fetched_at=COALESCE(excluded.detail_fetched_at, players.detail_fetched_at),
                    contacts_raw=COALESCE(excluded.contacts_raw, players.contacts_raw),
                    phone=COALESCE(excluded.phone, players.phone),
                    email=COALESCE(excluded.email, players.email),
                    telegram=COALESCE(excluded.telegram, players.telegram),
                    whatsapp=COALESCE(excluded.whatsapp, players.whatsapp),
                    updated_at=excluded.updated_at;

                INSERT INTO tournaments (
                    id, title, href, source_kind, status_class, date_text, club, club_id,
                    participants_count, participants_limit, comp_id, detail_json,
                    detail_fetched_at, source_page, created_at, updated_at
                )
                SELECT
                    id, title, href, source_kind, status_class, date_text, club, club_id,
                    participants_count, participants_limit, comp_id, detail_json,
                    detail_fetched_at, source_page, created_at, updated_at
                FROM shard.tournaments WHERE true
                ON CONFLICT(id) DO UPDATE SET
                    title=excluded.title,
                    href=excluded.href,
                    source_kind=excluded.source_kind,
                    status_class=excluded.status_class,
                    date_text=excluded.date_text,
                    club=excluded.club,
                    club_id=excluded.club_id,
                    participants_count=excluded.participants_count,
                    participants_limit=excluded.participants_limit,
                    comp_id=COALESCE(excluded.comp_id, tournaments.comp_id),
                    detail_json=COALESCE(excluded.detail_json, tournaments.detail_json),
                    detail_fetched_at=COALESCE(excluded.detail_fetched_at, tournaments.detail_fetched_at),
                    source_page=excluded.source_page,
                    updated_at=excluded.updated_at;

                INSERT OR REPLACE INTO tournament_stages (
                    comp_id, stage_id, tournament_id, name, fetched_at
                )
                SELECT comp_id, stage_id, tournament_id, name, fetched_at FROM shard.tournament_stages;

                INSERT OR REPLACE INTO tournament_participants (
                    comp_id, stage_id, player_id, seed, name, birth_year, rank,
                    country, city, place, fetched_at, avatar_url
                )
                SELECT
                    comp_id, stage_id, player_id, seed, name, birth_year, rank,
                    country, city, place, fetched_at, avatar_url
                FROM shard.tournament_participants;

                INSERT OR REPLACE INTO archive_tournament_participants (
                    tournament_id, membership_node_id, seed, name, level, points, place, fetched_at
                )
                SELECT
                    tournament_id, membership_node_id, seed, name, level, points, place, fetched_at
                FROM shard.archive_tournament_participants;

                INSERT OR REPLACE INTO archive_tournament_fetches (
                    tournament_id, status, rows_count, fetched_at
                )
                SELECT tournament_id, status, rows_count, fetched_at
                FROM shard.archive_tournament_fetches;

                INSERT OR REPLACE INTO matches (
                    comp_id, stage_id, game_no, tournament_id, round_name, status_class,
                    player1_id, player1_name, player1_elo_before, player1_elo_after,
                    player2_id, player2_name, player2_elo_before, player2_elo_after,
                    score1, score2, params, table_no, planned_at, started_at,
                    finished_at, video, raw_json, fetched_at
                )
                SELECT
                    comp_id, stage_id, game_no, tournament_id, round_name, status_class,
                    player1_id, player1_name, player1_elo_before, player1_elo_after,
                    player2_id, player2_name, player2_elo_before, player2_elo_after,
                    score1, score2, params, table_no, planned_at, started_at,
                    finished_at, video, raw_json, fetched_at
                FROM shard.matches;

                INSERT OR REPLACE INTO player_rating_events (
                    player_id, comp_id, stage_id, game_no, side, player_name,
                    elo_before, elo_after, fetched_at
                )
                SELECT
                    player_id, comp_id, stage_id, game_no, side, player_name,
                    elo_before, elo_after, fetched_at
                FROM shard.player_rating_events;

                INSERT OR REPLACE INTO player_ratings (
                    player_id, rating_key, discipline, rating_label, elo,
                    comps_year, comps_total, source, fetched_at
                )
                SELECT
                    player_id, rating_key, discipline, rating_label, elo,
                    comps_year, comps_total, source, fetched_at
                FROM shard.player_ratings;

                INSERT OR REPLACE INTO player_tournament_entries (
                    player_id, membership_node_id, tournament_id, title, date_text,
                    points, place, source_page, fetched_at
                )
                SELECT
                    player_id, membership_node_id, tournament_id, title, date_text,
                    points, place, source_page, fetched_at
                FROM shard.player_tournament_entries;
                """
            )
            self.conn.commit()
        finally:
            self.conn.execute("DETACH DATABASE shard")
        after = self.counts()
        return {key: after[key] - before.get(key, 0) for key in after}

    def ensure_attached_column(self, schema: str, table: str, column: str, column_type: str) -> None:
        existing = {row[1] for row in self.conn.execute(f"PRAGMA {schema}.table_info({table})")}
        if column not in existing:
            self.conn.execute(f"ALTER TABLE {schema}.{table} ADD COLUMN {column} {column_type}")

    def ensure_attached_table_player_ratings(self, schema: str) -> None:
        exists = self.conn.execute(
            "SELECT 1 FROM shard.sqlite_master WHERE type='table' AND name='player_ratings'"
            if schema == "shard"
            else f"SELECT 1 FROM {schema}.sqlite_master WHERE type='table' AND name='player_ratings'"
        ).fetchone()
        if not exists:
            self.conn.execute(
                f"""
                CREATE TABLE {schema}.player_ratings (
                    player_id INTEGER NOT NULL,
                    rating_key TEXT NOT NULL,
                    discipline TEXT,
                    rating_label TEXT,
                    elo INTEGER,
                    comps_year INTEGER,
                    comps_total INTEGER,
                    source TEXT NOT NULL,
                    fetched_at TEXT NOT NULL,
                    PRIMARY KEY (player_id, rating_key)
                )
                """
            )

    def ensure_attached_table_player_tournament_entries(self, schema: str) -> None:
        exists = self.conn.execute(
            "SELECT 1 FROM shard.sqlite_master WHERE type='table' AND name='player_tournament_entries'"
            if schema == "shard"
            else f"SELECT 1 FROM {schema}.sqlite_master WHERE type='table' AND name='player_tournament_entries'"
        ).fetchone()
        if not exists:
            self.conn.execute(
                f"""
                CREATE TABLE {schema}.player_tournament_entries (
                    player_id INTEGER NOT NULL,
                    membership_node_id INTEGER NOT NULL DEFAULT 0,
                    tournament_id INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    date_text TEXT,
                    points TEXT,
                    place TEXT,
                    source_page INTEGER,
                    fetched_at TEXT NOT NULL,
                    PRIMARY KEY (player_id, tournament_id, membership_node_id)
                )
                """
            )

    def ensure_attached_table_archive_tournament_participants(self, schema: str) -> None:
        exists = self.conn.execute(
            "SELECT 1 FROM shard.sqlite_master WHERE type='table' AND name='archive_tournament_participants'"
            if schema == "shard"
            else f"SELECT 1 FROM {schema}.sqlite_master WHERE type='table' AND name='archive_tournament_participants'"
        ).fetchone()
        if not exists:
            self.conn.execute(
                f"""
                CREATE TABLE {schema}.archive_tournament_participants (
                    tournament_id INTEGER NOT NULL,
                    membership_node_id INTEGER NOT NULL DEFAULT 0,
                    seed INTEGER,
                    name TEXT NOT NULL,
                    level TEXT,
                    points TEXT,
                    place TEXT,
                    fetched_at TEXT NOT NULL,
                    PRIMARY KEY (tournament_id, membership_node_id, name)
                )
                """
            )

    def ensure_attached_table_archive_tournament_fetches(self, schema: str) -> None:
        exists = self.conn.execute(
            "SELECT 1 FROM shard.sqlite_master WHERE type='table' AND name='archive_tournament_fetches'"
            if schema == "shard"
            else f"SELECT 1 FROM {schema}.sqlite_master WHERE type='table' AND name='archive_tournament_fetches'"
        ).fetchone()
        if not exists:
            self.conn.execute(
                f"""
                CREATE TABLE {schema}.archive_tournament_fetches (
                    tournament_id INTEGER PRIMARY KEY,
                    status TEXT NOT NULL,
                    rows_count INTEGER NOT NULL DEFAULT 0,
                    fetched_at TEXT NOT NULL
                )
                """
            )

    def counts(self) -> dict[str, int]:
        tables = [
            "players",
            "tournaments",
            "tournament_stages",
            "tournament_participants",
            "archive_tournament_participants",
            "archive_tournament_fetches",
            "matches",
            "player_rating_events",
            "player_ratings",
            "player_tournament_entries",
        ]
        return {table: int(self.conn.execute(f"SELECT count(*) FROM {table}").fetchone()[0]) for table in tables}

    def commit(self) -> None:
        self.conn.commit()


def parse_players(page: str, source_page: int) -> list[PlayerRow]:
    result = []
    for row in first_table_rows(page, content_class="view-content-players"):
        if len(row) < 5:
            continue
        links = row[0]["links"]
        if not isinstance(links, list) or not links:
            continue
        href = str(links[0]["href"])
        match = re.search(r"/node/(\d+)", href)
        if not match:
            continue
        country_links = row[2]["links"] if isinstance(row[2].get("links"), list) else []
        country_id = None
        if country_links:
            country_match = re.search(r"/node/(\d+)", str(country_links[0].get("href", "")))
            country_id = int(country_match.group(1)) if country_match else None
        result.append(
            PlayerRow(
                player_id=int(match.group(1)),
                name=clean_text(str(links[0].get("text", "")) or str(row[0]["text"])),
                href=href,
                birthday=clean_text(str(row[1]["text"])),
                country=clean_text(str(row[2]["text"])),
                country_id=country_id,
                city=clean_text(str(row[3]["text"])),
                registered_at=clean_text(str(row[4]["text"])),
                source_page=source_page,
            )
        )
    return result


def parse_tournaments(page: str, source_page: int, source_kind: str) -> list[TournamentRow]:
    result = []
    teaser_pattern = re.compile(r"(?is)<div class=\"comp-teaser-container\">(.*?)(?=<div class=\"comp-teaser-container\">|</div><div class=\"pager\">)")
    for teaser in teaser_pattern.findall(page):
        title_match = re.search(r"(?is)<div class=\"comp-teaser links-new\"><a href=\"(/t/(\d+))\">(.*?)</a>", teaser)
        if not title_match:
            continue
        date_match = re.search(r"(?is)<td\b[^>]*class=\"date\"[^>]*>(.*?)</td>", teaser)
        class_match = re.search(r"(?is)<table class=\"comp-teaser ([^\"]+)\"", teaser)
        club_match = re.search(r"(?is)<a class=\"comp-teaser club-link\" href=\"/node/(\d+)\">(.*?)</a>", teaser)
        participants_match = re.search(r"title=\"Участники:\s*(\d+)(?:\s+из\s+(\d+))?\"", teaser)
        result.append(
            TournamentRow(
                tournament_id=int(title_match.group(2)),
                title=clean_text(title_match.group(3)),
                href=title_match.group(1),
                source_kind=source_kind,
                status_class=clean_text(class_match.group(1) if class_match else ""),
                date_text=clean_text(date_match.group(1) if date_match else ""),
                club=clean_text(club_match.group(2) if club_match else ""),
                club_id=int(club_match.group(1)) if club_match else None,
                participants_count=int(participants_match.group(1)) if participants_match else None,
                participants_limit=int(participants_match.group(2)) if participants_match and participants_match.group(2) else None,
                source_page=source_page,
            )
        )
    return result


def parse_detail_fields(page: str) -> dict[str, object]:
    fields: dict[str, object] = {}
    for item in re.findall(r"(?is)<div class=\"field-item [^\"]+\">(.*?)</div></div></div>", page):
        label_match = re.search(r"(?is)<div class=\"field-label-inline-first\">(.*?)</div>", item)
        if not label_match:
            continue
        label = clean_text(label_match.group(1)).rstrip(":").strip()
        value_html = re.sub(r"(?is)<div class=\"field-label-inline-first\">.*?</div>", "", item, count=1)
        value = clean_text(value_html)
        if label and value:
            fields[label] = value
    legends = {}
    for fieldset in re.findall(r"(?is)<fieldset[^>]*>(.*?)</fieldset>", page):
        legend_match = re.search(r"(?is)<legend>(.*?)</legend>", fieldset)
        if legend_match:
            legend = clean_text(legend_match.group(1))
            text = clean_text(fieldset)
            if legend and text:
                legends[legend] = text
    comp_match = re.search(r"competition\.php\?comp=(\d+)", page)
    if comp_match:
        fields["comp_id"] = int(comp_match.group(1))
    if legends:
        fields["_sections"] = legends
    return fields


EMAIL_RE = re.compile(r"(?i)\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b")
PHONE_RE = re.compile(r"(?:(?:\+7|8)[\s()\-]*\d(?:[\s()\-]*\d){9}|\b\d{10,11}\b)")
TELEGRAM_RE = re.compile(r"(?i)(?:https?://)?(?:t\.me|telegram\.me)/([A-Za-z0-9_]{4,32})|(?<![\w@])@([A-Za-z0-9_]{4,32})")


def contact_raw_from_detail(detail: dict[str, object]) -> str:
    direct = clean_text(str(detail.get("Контакты", "") or ""))
    if direct:
        return direct
    sections = detail.get("_sections")
    if isinstance(sections, dict):
        for value in sections.values():
            text = clean_text(str(value))
            match = re.search(r"Контакты:\s*(.+?)(?:\s+[А-ЯЁ][а-яё\s-]{2,}:|$)", text)
            if match:
                return clean_text(match.group(1))
    return ""


def normalize_phone(value: str) -> str | None:
    digits = re.sub(r"\D+", "", value)
    if len(digits) == 10:
        digits = "7" + digits
    elif len(digits) == 11 and digits.startswith("8"):
        digits = "7" + digits[1:]
    if len(digits) != 11 or not digits.startswith("7"):
        return None
    return "+" + digits


def unique_join(values: list[str]) -> str | None:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        cleaned = clean_text(value).strip(" ,;")
        key = cleaned.lower()
        if cleaned and key not in seen:
            seen.add(key)
            result.append(cleaned)
    return ", ".join(result) if result else None


def extract_contact_fields(detail: dict[str, object]) -> dict[str, str | None]:
    raw = contact_raw_from_detail(detail)
    phones = [phone for phone in (normalize_phone(match.group(0)) for match in PHONE_RE.finditer(raw)) if phone]
    emails = [match.group(0) for match in EMAIL_RE.finditer(raw)]
    telegrams = [next(group for group in match.groups() if group) for match in TELEGRAM_RE.finditer(raw)]
    lower_raw = raw.lower()
    telegram = unique_join(telegrams)
    whatsapp = None
    if not telegram and "telegram" in lower_raw and phones:
        telegram = phones[0]
    if ("whatsapp" in lower_raw or "wats" in lower_raw or "ватс" in lower_raw) and phones:
        whatsapp = phones[0]
    return {
        "contacts_raw": raw or None,
        "phone": unique_join(phones),
        "email": unique_join(emails),
        "telegram": telegram,
        "whatsapp": whatsapp,
    }


def parse_player_ratings(fragment: str) -> list[dict[str, object]]:
    ratings: list[dict[str, object]] = []
    for fieldset_match in re.finditer(r"(?is)<fieldset\b([^>]*)>(.*?)</fieldset>", fragment):
        attrs, fieldset = fieldset_match.groups()
        legend_match = re.search(r"(?is)<legend>(.*?)</legend>", fieldset)
        legend = clean_text(legend_match.group(1)) if legend_match else ""
        class_match = re.search(r"class=[\"']([^\"']+)[\"']", attrs)
        class_names = class_match.group(1) if class_match else ""
        if "group-llb" not in class_names and not legend.startswith("ЛЛБ"):
            continue
        group_match = re.search(r"\bgroup-([a-z0-9_-]*llb[a-z0-9_-]*)\b|\bgroup-(llb[a-z0-9_-]*)\b", class_names)
        rating_key = next((group for group in (group_match.groups() if group_match else ()) if group), None)
        if not rating_key:
            rating_key = re.sub(r"[^a-z0-9]+", "-", legend.lower()).strip("-") or "llb"
        item = {
            "rating_key": rating_key,
            "discipline": legend,
            "rating_label": "Рейтинг Эло",
            "source": "player_detail",
        }
        for field_match in re.finditer(
            r"(?is)<div class=\"field\b[^>]*field-field-([^\"]+)\"[^>]*>.*?"
            r"<div class=\"field-label-inline-first\">(.*?)</div>(.*?)</div></div></div>",
            fieldset,
        ):
            field_key, label_html, value_html = field_match.groups()
            label = clean_text(label_html).rstrip(":").strip().lower()
            value = to_int(clean_text(value_html))
            if value is None:
                continue
            if field_key.endswith("-elo") or "рейтинг эло" in label:
                if field_key.endswith("-elo"):
                    item["rating_key"] = field_key[: -len("-elo")]
                item["elo"] = value
            elif field_key.endswith("-comps-year") or "последний год" in label:
                if field_key.endswith("-comps-year") and item["rating_key"] == "llb":
                    item["rating_key"] = field_key[: -len("-comps-year")]
                item["comps_year"] = value
            elif field_key.endswith("-comps") or "всего" in label:
                if field_key.endswith("-comps") and item["rating_key"] == "llb":
                    item["rating_key"] = field_key[: -len("-comps")]
                item["comps_total"] = value
        if item.get("elo") is not None or item.get("comps_year") is not None or item.get("comps_total") is not None:
            ratings.append(item)
    return ratings


def parse_player_detail(page: str) -> tuple[dict[str, object], int | None, str | None, list[dict[str, object]]]:
    detail = parse_detail_fields(page)
    title_match = re.search(r"(?is)<h1\b[^>]*>(.*?)</h1>", page)
    if title_match:
        title = clean_text(title_match.group(1))
        if title:
            detail["name"] = title
    node_match = re.search(r"(?is)<div class=\"node\b.*?</div>\s*</div>\s*<!-- /content -->", page)
    fragment = node_match.group(0) if node_match else page
    avatar_url = first_image_url(fragment)
    if avatar_url:
        detail["avatar_url"] = avatar_url
    ratings = parse_player_ratings(fragment)
    if ratings:
        detail["_ratings"] = ratings
    full_text = clean_text(fragment)
    rating_lines = []
    for line in full_text.splitlines():
        if re.search(r"(?i)(эло|elo|рейтинг|rating)", line):
            rating_lines.append(line[:500])
    rating_text = "\n".join(dict.fromkeys(rating_lines)) or None
    if rating_text:
        detail["_rating_hits"] = rating_text
    elo_values = [rating.get("elo") for rating in ratings if rating.get("elo") is not None]
    elo = int(elo_values[0]) if elo_values else None
    return detail, elo, rating_text, ratings


def parse_player_tournament_entries(page: str, player_id: int, source_page: int) -> list[PlayerTournamentEntry]:
    def plain_node_id(href: str) -> int | None:
        parsed = urllib.parse.urlparse(href)
        if parsed.query:
            return None
        match = re.fullmatch(r".*/?node/(\d+)/?", parsed.path)
        return int(match.group(1)) if match else None

    entries: list[PlayerTournamentEntry] = []
    rows = [
        *first_table_rows(page, content_class="view-player-members"),
        *first_table_rows(page, content_class="view-player-parts"),
    ]
    for row in rows:
        tournament_id: int | None = None
        title = ""
        tournament_cell_index: int | None = None
        membership_node_id: int | None = None

        for cell_index, cell in enumerate(row):
            links = cell.get("links")
            if not isinstance(links, list):
                continue
            for link in links:
                href = str(link.get("href", ""))
                node_id = plain_node_id(href)
                if membership_node_id is None:
                    if node_id is not None:
                        membership_node_id = node_id
                tournament_match = re.search(r"/t/(\d+)", href)
                if tournament_match:
                    tournament_id = int(tournament_match.group(1))
                    title = clean_text(str(link.get("text", "")))
                    tournament_cell_index = cell_index
                    break
                if node_id is not None and cell_index > 0:
                    link_text = clean_text(str(link.get("text", "")))
                    if link_text and link_text != ">>>":
                        tournament_id = node_id
                        title = link_text
                        tournament_cell_index = cell_index
                        break
            if tournament_id is not None:
                break

        if tournament_id is None or title == "" or tournament_cell_index is None:
            continue

        date_candidates = [
            clean_text(str(row[index]["text"]))
            for index in range(0, tournament_cell_index)
            if clean_text(str(row[index]["text"])) and clean_text(str(row[index]["text"])) != ">>>"
        ]
        trailing = [
            clean_text(str(row[index]["text"]))
            for index in range(tournament_cell_index + 1, len(row))
        ]
        entries.append(
            PlayerTournamentEntry(
                player_id=player_id,
                membership_node_id=membership_node_id,
                tournament_id=tournament_id,
                title=title,
                date_text=date_candidates[-1] if date_candidates else "",
                points=trailing[0] if trailing else "",
                place=trailing[1] if len(trailing) > 1 else "",
                source_page=source_page,
            )
        )
    return entries


def parse_title(page: str) -> str:
    match = re.search(r"(?is)<h1\b[^>]*class=[\"'][^\"']*\btitle\b[^\"']*[\"'][^>]*>(.*?)</h1>", page)
    if match:
        return clean_text(match.group(1))
    match = re.search(r"(?is)<title>(.*?)</title>", page)
    if not match:
        return ""
    return clean_text(match.group(1)).split("|")[0].strip()


def node_id_from_href(href: str) -> int | None:
    parsed = urllib.parse.urlparse(href)
    if parsed.query:
        return None
    match = re.fullmatch(r".*/?node/(\d+)/?", parsed.path)
    return int(match.group(1)) if match else None


def parse_archive_tournament_participants(page: str, tournament_id: int) -> list[ArchiveTournamentParticipant]:
    rows = first_table_rows(page)
    result: list[ArchiveTournamentParticipant] = []
    active_columns: dict[str, int] | None = None
    for row in rows:
        labels = [clean_text(str(cell.get("text", ""))).lower() for cell in row]
        if any("участник турнира" in label for label in labels):
            active_columns = {}
            for index, label in enumerate(labels):
                if label in {"№", "n", "#"} or label.startswith("№"):
                    active_columns["seed"] = index
                elif "участник турнира" in label:
                    active_columns["name"] = index
                elif "уровень" in label:
                    active_columns["level"] = index
                elif "очк" in label:
                    active_columns["points"] = index
                elif "место" in label:
                    active_columns["place"] = index
            if "name" not in active_columns:
                active_columns = None
            continue
        if not active_columns:
            continue
        name_index = active_columns["name"]
        if len(row) <= name_index:
            continue
        name_cell = row[name_index]
        links = name_cell.get("links")
        if not isinstance(links, list) or not links:
            continue
        href = str(links[0].get("href", ""))
        membership_node_id = node_id_from_href(href)
        name = clean_text(str(links[0].get("text", "")) or str(name_cell.get("text", "")))
        if not name:
            continue

        def cell_text(key: str) -> str:
            index = active_columns.get(key)
            if index is None or len(row) <= index:
                return ""
            return clean_text(str(row[index].get("text", "")))

        result.append(
            ArchiveTournamentParticipant(
                tournament_id=tournament_id,
                membership_node_id=membership_node_id,
                seed=to_int(cell_text("seed")),
                name=name,
                level=cell_text("level"),
                points=cell_text("points"),
                place=cell_text("place"),
            )
        )
    return result


def parse_competition_stages(page: str) -> list[tuple[int, str]]:
    stages: list[tuple[int, str]] = []
    seen = set()
    for href, label in re.findall(r"(?is)<a[^>]+href=\"[^\"]*comp=\d+&stage=(\d+)[^\"]*\"[^>]*>(.*?)</a>", page):
        stage_id = int(href)
        if stage_id in seen:
            continue
        seen.add(stage_id)
        stages.append((stage_id, clean_text(label)))
    return stages


def player_from_link(cell: dict[str, object], index: int) -> tuple[int | None, str | None]:
    links = cell.get("links")
    if not isinstance(links, list) or len(links) <= index:
        lines = [clean_text(line) for line in re.split(r"\n|<br\s*/?>", str(cell.get("html", ""))) if clean_text(line)]
        return None, lines[index] if len(lines) > index else None
    link = links[index]
    href = str(link.get("href", ""))
    match = re.search(r"[?&]id=(\d+)|/node/(\d+)", href)
    player_id = int(next(group for group in match.groups() if group)) if match else None
    return player_id, clean_text(str(link.get("text", "")))


def player_info_from_cell(cell: dict[str, object], index: int) -> tuple[int | None, str | None, int | None, int | None]:
    player_id, name = player_from_link(cell, index)
    lines = [clean_text(line) for line in re.split(r"(?i)<br\s*/?>|\n", str(cell.get("html", ""))) if clean_text(line)]
    rating_source = lines[index] if len(lines) > index else name
    _, before, after = split_rating_suffix(rating_source)
    return player_id, name, before, after


def parse_score_cell(cell: dict[str, object]) -> tuple[str | None, str | None]:
    html_value = str(cell.get("html", ""))
    text_value = clean_text(str(cell.get("text", "")))
    pieces = [clean_text(piece) for piece in re.split(r"(?i)<br\s*/?>|\n", html_value) if clean_text(piece)]
    if len(pieces) >= 2:
        return pieces[0], pieces[1]
    numbers = re.findall(r"\d+", text_value)
    if len(numbers) >= 2:
        return numbers[0], numbers[1]
    return None, None


def split_rating_suffix(name: str | None) -> tuple[str | None, int | None, int | None]:
    if not name:
        return None, None, None
    match = re.search(r"\s+(\d{2,5})\s*[→\-–]\s*(\d{2,5})\s*$", name)
    if not match:
        return clean_text(name), None, None
    return clean_text(name[: match.start()]), int(match.group(1)), int(match.group(2))


def parse_matches(page: str) -> list[dict[str, object]]:
    result = []
    for row in first_table_rows(page, table_id="matches"):
        if len(row) < 10:
            continue
        game_no = to_int(clean_text(str(row[0]["text"])))
        if game_no is None:
            continue
        player1_id, player1_name, player1_elo_before, player1_elo_after = player_info_from_cell(row[2], 0)
        player2_id, player2_name, player2_elo_before, player2_elo_after = player_info_from_cell(row[2], 1)
        score1, score2 = parse_score_cell(row[3])
        attrs = row[0].get("attrs", {})
        class_name = attrs.get("class", "") if isinstance(attrs, dict) else ""
        result.append(
            {
                "game_no": game_no,
                "round_name": clean_text(str(row[1]["text"])),
                "status_class": class_name,
                "player1_id": player1_id,
                "player1_name": player1_name,
                "player1_elo_before": player1_elo_before,
                "player1_elo_after": player1_elo_after,
                "player2_id": player2_id,
                "player2_name": player2_name,
                "player2_elo_before": player2_elo_before,
                "player2_elo_after": player2_elo_after,
                "score1": score1,
                "score2": score2,
                "params": clean_text(str(row[4]["text"])),
                "table_no": clean_text(str(row[5]["text"])),
                "planned_at": clean_text(str(row[6]["text"])),
                "started_at": clean_text(str(row[7]["text"])),
                "finished_at": clean_text(str(row[8]["text"])),
                "video": clean_text(str(row[9]["text"])),
            }
        )
    return result


def parse_participants(page: str) -> list[dict[str, object]]:
    result = []
    for row in first_table_rows(page, table_id="participants"):
        if len(row) < 7:
            continue
        links = row[1].get("links")
        if not isinstance(links, list) or not links:
            continue
        href = str(links[0].get("href", ""))
        player_match = re.search(r"[?&]id=(\d+)|/node/(\d+)", href)
        player_id = int(next(group for group in player_match.groups() if group)) if player_match else None
        avatar_url = first_image_url(str(row[1].get("html", "")), base=TOURNAMENT_BASE)
        result.append(
            {
                "seed": to_int(clean_text(str(row[0]["text"]))),
                "player_id": player_id,
                "name": clean_text(str(links[0].get("text", ""))),
                "birth_year": clean_text(str(row[2]["text"])),
                "rank": clean_text(str(row[3]["text"])),
                "country": clean_text(str(row[4]["text"])),
                "city": clean_text(str(row[5]["text"])),
                "place": clean_text(str(row[6]["text"])),
                "avatar_url": avatar_url,
            }
        )
    return result


class Scraper:
    def __init__(self, client: HttpClient, db: Database):
        self.client = client
        self.db = db

    def import_players(self, start_page: int, limit_pages: int | None) -> None:
        first = self.client.request("/players" if start_page == 0 else f"/players?page={start_page}")
        last_page = max_page(first)
        pages = range(start_page, last_page + 1)
        if limit_pages is not None:
            pages = range(start_page, min(start_page + limit_pages, last_page + 1))
        for page_no in pages:
            page = first if page_no == start_page else self.client.request("/players" if page_no == 0 else f"/players?page={page_no}")
            rows = parse_players(page, page_no)
            for row in rows:
                self.db.upsert_player(row)
            self.db.commit()
            print(f"players page={page_no}/{last_page} rows={len(rows)}", flush=True)

    def import_player_details(self, limit: int | None, force: bool) -> None:
        ids = self.db.player_ids_for_details(limit, force)
        total = len(ids)
        for index, player_id in enumerate(ids, start=1):
            try:
                page = self.client.request(f"/node/{player_id}")
            except HttpStatusError as exc:
                if exc.code in {403, 404}:
                    detail = {
                        "_error": f"http_{exc.code}",
                        "_url": exc.url,
                        "_message": clean_text(exc.body.decode("utf-8", errors="replace"))[:500],
                    }
                    self.db.upsert_player_detail(player_id, detail, None, None, [])
                    self.db.commit()
                    print(f"player detail {index}/{total} id={player_id} skipped=http_{exc.code}", flush=True)
                    continue
                raise
            detail, elo, rating_text, ratings = parse_player_detail(page)
            self.db.upsert_player_detail(player_id, detail, elo, rating_text, ratings)
            self.db.commit()
            print(f"player detail {index}/{total} id={player_id} elo={elo} ratings={len(ratings)}", flush=True)

    def import_player_tournaments(self, ids: list[int] | None, limit: int | None) -> None:
        player_ids = self.db.player_ids_for_tournament_entries(ids, limit)
        total = len(player_ids)
        for index, player_id in enumerate(player_ids, start=1):
            first = self.client.request(f"/node/{player_id}")
            last_page = max_page(first)
            entries: list[PlayerTournamentEntry] = []
            for page_no in range(0, last_page + 1):
                page = first if page_no == 0 else self.client.request(f"/node/{player_id}?page={page_no}")
                entries.extend(parse_player_tournament_entries(page, player_id, page_no))
            unique_entries = {
                (entry.tournament_id, entry.membership_node_id): entry
                for entry in entries
            }
            self.db.replace_player_tournament_entries(player_id, list(unique_entries.values()))
            self.db.commit()
            print(
                f"player tournaments {index}/{total} id={player_id} pages={last_page + 1} entries={len(unique_entries)}",
                flush=True,
            )

    def import_tournaments(self, kind: str, start_page: int, limit_pages: int | None) -> None:
        path = "/tournaments/results" if kind == "results" else f"/tournaments/{kind}"
        first = self.client.request(path if start_page == 0 else f"{path}?page={start_page}")
        last_page = max_page(first)
        pages = range(start_page, last_page + 1)
        if limit_pages is not None:
            pages = range(start_page, min(start_page + limit_pages, last_page + 1))
        for page_no in pages:
            page = first if page_no == start_page else self.client.request(path if page_no == 0 else f"{path}?page={page_no}")
            rows = parse_tournaments(page, page_no, kind)
            for row in rows:
                self.db.upsert_tournament(row)
            self.db.commit()
            print(f"tournaments kind={kind} page={page_no}/{last_page} rows={len(rows)}", flush=True)

    def import_tournament_details(
        self,
        limit: int | None,
        force: bool,
        source_kinds: list[str] | None = None,
    ) -> None:
        ids = self.db.tournament_ids_for_details(limit, force, source_kinds)
        total = len(ids)
        for index, tournament_id in enumerate(ids, start=1):
            page = self.client.request(f"/t/{tournament_id}")
            detail = parse_detail_fields(page)
            comp_id = detail.get("comp_id")
            self.db.upsert_tournament_detail(tournament_id, detail, int(comp_id) if comp_id else None)
            self.db.commit()
            print(f"tournament detail {index}/{total} id={tournament_id} comp={comp_id}", flush=True)

    def import_archive_tournament_participants(self, ids: list[int] | None, limit: int | None) -> None:
        tournament_ids = self.db.archive_tournament_ids_for_participants(ids, limit)
        total = len(tournament_ids)
        for index, tournament_id in enumerate(tournament_ids, start=1):
            try:
                page = self.client.request(f"/node/{tournament_id}")
            except HttpStatusError as exc:
                if exc.code in {403, 404}:
                    self.db.mark_archive_tournament_fetched(tournament_id, f"http_{exc.code}", 0)
                    self.db.commit()
                    print(f"archive participants {index}/{total} id={tournament_id} skipped=http_{exc.code}", flush=True)
                    continue
                raise
            title = parse_title(page)
            participants = parse_archive_tournament_participants(page, tournament_id)
            self.db.upsert_archive_tournament_shell(tournament_id, title)
            self.db.replace_archive_tournament_participants(tournament_id, participants)
            self.db.mark_archive_tournament_fetched(tournament_id, "ok" if participants else "empty", len(participants))
            self.db.commit()
            print(
                f"archive participants {index}/{total} id={tournament_id} rows={len(participants)}",
                flush=True,
            )

    def import_matches(
        self,
        limit_competitions: int | None,
        force: bool = False,
        source_kinds: list[str] | None = None,
        replace_existing: bool = False,
    ) -> None:
        competitions = self.db.competitions_for_matches(limit_competitions, force, source_kinds)
        for comp_index, row in enumerate(competitions, start=1):
            tournament_id = int(row["id"])
            comp_id = int(row["comp_id"])
            if replace_existing:
                self.db.clear_competition_data(tournament_id, comp_id)
                self.db.commit()
            try:
                comp_page = self.client.request(f"/competition.php?comp={comp_id}", base=TOURNAMENT_BASE)
            except HttpStatusError as exc:
                if exc.code >= 500 and exc.body:
                    comp_page = exc.body.decode("utf-8", errors="replace")
                    print(f"competition {comp_index}/{len(competitions)} tournament={tournament_id} comp={comp_id} http_{exc.code}=using_body", flush=True)
                else:
                    print(f"competition {comp_index}/{len(competitions)} tournament={tournament_id} comp={comp_id} skipped=http_{exc.code}", flush=True)
                    self.db.mark_competition_matches_fetched(tournament_id, comp_id)
                    self.db.commit()
                    continue
            stages = parse_competition_stages(comp_page)
            if not stages:
                active = re.search(r"stage=(\d+)", comp_page)
                if active:
                    stages = [(int(active.group(1)), "")]
            print(f"competition {comp_index}/{len(competitions)} tournament={tournament_id} comp={comp_id} stages={len(stages)}", flush=True)
            for stage_id, stage_name in stages:
                self.db.upsert_stage(comp_id, stage_id, tournament_id, stage_name)
                try:
                    participants_page = self.client.request(f"/participants.php?comp={comp_id}&stage={stage_id}", base=TOURNAMENT_BASE)
                except HttpStatusError as exc:
                    if exc.code >= 500 and exc.body:
                        participants_page = exc.body.decode("utf-8", errors="replace")
                        print(f"  stage={stage_id} participants http_{exc.code}=using_body", flush=True)
                    else:
                        print(f"  stage={stage_id} participants skipped=http_{exc.code}", flush=True)
                        participants_page = ""
                try:
                    matches_page = self.client.request(f"/matches.php?comp={comp_id}&stage={stage_id}", base=TOURNAMENT_BASE)
                except HttpStatusError as exc:
                    if exc.code >= 500 and exc.body:
                        matches_page = exc.body.decode("utf-8", errors="replace")
                        print(f"  stage={stage_id} matches http_{exc.code}=using_body", flush=True)
                    else:
                        print(f"  stage={stage_id} matches skipped=http_{exc.code}", flush=True)
                        matches_page = ""
                participants = parse_participants(participants_page)
                matches = parse_matches(matches_page)
                for participant in participants:
                    self.db.upsert_participant(comp_id, stage_id, participant)
                for match in matches:
                    self.db.upsert_match(comp_id, stage_id, tournament_id, match)
                self.db.commit()
                print(f"  stage={stage_id} participants={len(participants)} matches={len(matches)}", flush=True)
            self.db.mark_competition_matches_fetched(tournament_id, comp_id)
            self.db.commit()

    def import_shard(
        self,
        player_start_page: int,
        player_pages: int | None,
        player_details: int | None,
        tournament_start_page: int,
        tournament_pages: int | None,
        tournament_details: int | None,
        competitions: int | None,
    ) -> None:
        self.import_players(player_start_page, player_pages)
        self.import_player_details(player_details, False)
        self.import_tournaments("results", tournament_start_page, tournament_pages)
        self.import_tournament_details(tournament_details, False)
        self.import_matches(competitions)


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--db", default="data/llb.sqlite3", help="SQLite database path.")
    parser.add_argument("--username", default=os.getenv("LLB_USERNAME"), help="LLB login; can also use LLB_USERNAME.")
    parser.add_argument("--password", default=os.getenv("LLB_PASSWORD"), help="LLB password; can also use LLB_PASSWORD.")
    parser.add_argument("--cookies", default="data/llb_cookies.txt", help="Cookie jar path for reusing login sessions.")
    parser.add_argument("--sleep", type=float, default=0.35, help="Delay between HTTP requests in seconds.")
    parser.add_argument("--login", action="store_true", help="Login before scraping.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Import llb.su data into SQLite.")
    add_common_args(parser)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("login-check", help="Check credentials and exit.")

    players = sub.add_parser("players", help="Import paginated players list.")
    players.add_argument("--start-page", type=int, default=0)
    players.add_argument("--limit-pages", type=int)

    details = sub.add_parser("player-details", help="Fetch player detail pages for ELO/rating fields.")
    details.add_argument("--limit", type=int)
    details.add_argument("--force", action="store_true")

    player_tournaments = sub.add_parser("player-tournaments", help="Fetch tournament history from player profile pages.")
    player_tournaments.add_argument("--id", dest="ids", action="append", type=int)
    player_tournaments.add_argument("--limit", type=int)

    tournaments = sub.add_parser("tournaments", help="Import tournament teasers.")
    tournaments.add_argument("--kind", choices=["results", "online", "next"], default="results")
    tournaments.add_argument("--start-page", type=int, default=0)
    tournaments.add_argument("--limit-pages", type=int)

    tournament_details = sub.add_parser("tournament-details", help="Fetch tournament pages and comp ids.")
    tournament_details.add_argument("--limit", type=int)
    tournament_details.add_argument("--force", action="store_true")
    tournament_details.add_argument("--source-kind", action="append", choices=["results", "online", "next"])

    archive_participants = sub.add_parser("archive-participants", help="Fetch participants from old /node tournament pages.")
    archive_participants.add_argument("--id", dest="ids", action="append", type=int)
    archive_participants.add_argument("--limit", type=int)

    matches = sub.add_parser("matches", help="Fetch stages, participants and matches for known comp ids.")
    matches.add_argument("--limit-competitions", type=int)
    matches.add_argument("--force", action="store_true")
    matches.add_argument("--source-kind", action="append", choices=["results", "online", "next"])
    matches.add_argument("--replace-existing", action="store_true")

    all_full = sub.add_parser("all", help="Full resumable import. Use limits for staged runs.")
    all_full.add_argument("--player-pages", type=int)
    all_full.add_argument("--player-details", type=int)
    all_full.add_argument("--tournament-pages", type=int)
    all_full.add_argument("--tournament-details", type=int)
    all_full.add_argument("--competitions", type=int)

    shard = sub.add_parser("shard", help="Run one bounded shard into its own SQLite DB.")
    shard.add_argument("--player-start-page", type=int, default=0)
    shard.add_argument("--player-pages", type=int)
    shard.add_argument("--player-details", type=int)
    shard.add_argument("--tournament-start-page", type=int, default=0)
    shard.add_argument("--tournament-pages", type=int)
    shard.add_argument("--tournament-details", type=int)
    shard.add_argument("--competitions", type=int)

    merge = sub.add_parser("merge", help="Merge one or more shard SQLite DBs into --db.")
    merge.add_argument("shards", nargs="+")

    all_cmd = sub.add_parser("sample-all", help="Small smoke import for all entity types.")
    all_cmd.add_argument("--player-pages", type=int, default=1)
    all_cmd.add_argument("--player-details", type=int, default=3)
    all_cmd.add_argument("--tournament-pages", type=int, default=1)
    all_cmd.add_argument("--tournament-details", type=int, default=3)
    all_cmd.add_argument("--competitions", type=int, default=1)
    return parser


def maybe_login(args: argparse.Namespace, client: HttpClient) -> None:
    if args.login or args.command in {"login-check", "player-details", "player-tournaments"}:
        ok = client.ensure_login()
        if not ok:
            raise SystemExit("Login failed. Check LLB_USERNAME/LLB_PASSWORD or pass --username/--password.")
        print("login ok" if client.logged_in else "session ok", flush=True)


def main(argv: list[str] | None = None) -> int:
    install_host_overrides(os.getenv("LLB_HOST_OVERRIDES"))
    args = build_parser().parse_args(argv)
    client = HttpClient(args.username, args.password, args.sleep, Path(args.cookies) if args.cookies else None)
    db = Database(Path(args.db))
    maybe_login(args, client)
    scraper = Scraper(client, db)

    if args.command == "login-check":
        return 0
    if args.command == "players":
        scraper.import_players(args.start_page, args.limit_pages)
    elif args.command == "player-details":
        scraper.import_player_details(args.limit, args.force)
    elif args.command == "player-tournaments":
        scraper.import_player_tournaments(args.ids, args.limit)
    elif args.command == "tournaments":
        scraper.import_tournaments(args.kind, args.start_page, args.limit_pages)
    elif args.command == "tournament-details":
        scraper.import_tournament_details(args.limit, args.force, args.source_kind)
    elif args.command == "archive-participants":
        scraper.import_archive_tournament_participants(args.ids, args.limit)
    elif args.command == "matches":
        scraper.import_matches(args.limit_competitions, args.force, args.source_kind, args.replace_existing)
    elif args.command == "all":
        if args.username and args.password and not client.logged_in:
            client.ensure_login()
        scraper.import_players(0, args.player_pages)
        scraper.import_player_details(args.player_details, False)
        scraper.import_tournaments("results", 0, args.tournament_pages)
        scraper.import_tournament_details(args.tournament_details, False)
        scraper.import_matches(args.competitions)
    elif args.command == "shard":
        if args.username and args.password and not client.logged_in:
            client.ensure_login()
        scraper.import_shard(
            args.player_start_page,
            args.player_pages,
            args.player_details,
            args.tournament_start_page,
            args.tournament_pages,
            args.tournament_details,
            args.competitions,
        )
    elif args.command == "merge":
        for shard_path in args.shards:
            delta = db.merge_from(Path(shard_path))
            print(f"merged {shard_path}: {delta}", flush=True)
    elif args.command == "sample-all":
        if args.username and args.password and not client.logged_in:
            client.ensure_login()
        scraper.import_players(0, args.player_pages)
        scraper.import_player_details(args.player_details, False)
        scraper.import_tournaments("results", 0, args.tournament_pages)
        scraper.import_tournament_details(args.tournament_details, False)
        scraper.import_matches(args.competitions)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
