#!/usr/bin/env python3
import argparse
import html
import json
import re
import time
import urllib.parse
import urllib.request
from html.parser import HTMLParser


LLB_BASE = "https://www.llb.su"
API_BASE = "https://llb.panfilius.ru/llb-api/"


class ClubsTableParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_row = False
        self.in_cell = False
        self.current_cell = []
        self.current_cells = []
        self.current_link = ""
        self.current_image = ""
        self.rows = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "tr":
            self.in_row = True
            self.current_cells = []
            self.current_link = ""
            self.current_image = ""
        elif self.in_row and tag == "td":
            self.in_cell = True
            self.current_cell = []
        elif self.in_row and tag == "a":
            href = attrs.get("href", "")
            if href.startswith("/club/"):
                self.current_link = href
        elif self.in_row and tag == "img":
            src = attrs.get("src", "")
            if src:
                self.current_image = absolute_url(src)

    def handle_endtag(self, tag):
        if tag == "td" and self.in_cell:
            text = html.unescape("".join(self.current_cell))
            self.current_cells.append(normalize_space(text))
            self.in_cell = False
        elif tag == "tr" and self.in_row:
            if self.current_link and len(self.current_cells) >= 7:
                self.rows.append(
                    {
                        "llb_id": self.current_link.rsplit("/", 1)[-1],
                        "name": self.current_cells[1],
                        "city": self.current_cells[2],
                        "image_url": self.current_image,
                        "tables_pyramid": int_or_none(self.current_cells[3]),
                        "tables_pool": int_or_none(self.current_cells[4]),
                        "tables_snooker": int_or_none(self.current_cells[5]),
                        "tables_total": int_or_none(self.current_cells[6]),
                    }
                )
            self.in_row = False

    def handle_data(self, data):
        if self.in_cell:
            self.current_cell.append(data)


def normalize_space(value):
    return re.sub(r"\s+", " ", value or "").strip()


def int_or_none(value):
    value = normalize_space(value)
    return int(value) if value.isdigit() else None


def absolute_url(value):
    value = value.strip()
    if value.startswith("http://") or value.startswith("https://"):
        return value
    if value.startswith("//"):
        return "https:" + value
    return LLB_BASE + "/" + value.lstrip("/")


def get_json(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": "llb-club-import/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def get_text(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": "llb-club-import/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


def post_json(url, payload, timeout=20):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "llb-club-import/1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def parse_page(page):
    url = f"{LLB_BASE}/clubs?page={page}"
    parser = ClubsTableParser()
    parser.feed(get_text(url))
    return parser.rows


def last_page():
    text = get_text(f"{LLB_BASE}/clubs?page=0")
    matches = [int(value) for value in re.findall(r"/clubs\?page=(\d+)", text)]
    return max(matches) if matches else 0


def mapbox_token(api_base):
    data = get_json(api_base.rstrip("/") + "/?resource=app_config")
    return normalize_space(data.get("mapbox_access_token", ""))


def geocode(row, token):
    if not token:
        return None, None
    query = f"{row['name']}, {row['city']}, Россия"
    params = urllib.parse.urlencode(
        {
            "q": query,
            "language": "ru",
            "country": "ru",
            "limit": "1",
            "access_token": token,
        }
    )
    url = f"https://api.mapbox.com/search/searchbox/v1/forward?{params}"
    try:
        data = get_json(url)
    except Exception:
        return None, None
    features = data.get("features") or []
    if not features:
        return None, None
    coordinates = (features[0].get("properties") or {}).get("coordinates") or {}
    lat = coordinates.get("latitude")
    lon = coordinates.get("longitude")
    if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
        return float(lat), float(lon)
    return None, None


def import_clubs(args):
    token = args.mapbox_token or mapbox_token(args.api_base)
    pages = args.pages if args.pages is not None else last_page() + 1
    imported = 0
    skipped = 0
    seen = set()
    for page in range(args.start_page, args.start_page + pages):
        rows = parse_page(page)
        if not rows:
            break
        for row in rows:
            key = (row["city"].lower(), row["name"].lower())
            if key in seen:
                continue
            seen.add(key)
            lat, lon = geocode(row, token) if args.geocode else (None, None)
            if args.require_coordinates and (lat is None or lon is None):
                skipped += 1
                continue
            payload = {
                **row,
                "created_by": "llb-clubs-import",
            }
            if lat is not None and lon is not None:
                payload["latitude"] = lat
                payload["longitude"] = lon
            post_json(args.api_base.rstrip("/") + "/?resource=clubs", payload)
            imported += 1
            if args.sleep > 0:
                time.sleep(args.sleep)
        print(f"page={page} imported={imported} skipped={skipped}", flush=True)
    print(json.dumps({"imported": imported, "skipped": skipped}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--api-base", default=API_BASE)
    parser.add_argument("--mapbox-token", default="")
    parser.add_argument("--start-page", type=int, default=0)
    parser.add_argument("--pages", type=int)
    parser.add_argument("--geocode", action="store_true")
    parser.add_argument("--require-coordinates", action="store_true")
    parser.add_argument("--sleep", type=float, default=0.05)
    import_clubs(parser.parse_args())


if __name__ == "__main__":
    main()
