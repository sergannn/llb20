#!/usr/bin/env python3
"""Print distributed LLB ELO worker progress from local and SSH shards."""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Worker:
    name: str
    db_path: str
    pid_path: str
    alt_pid_path: str | None = None
    ssh: str | None = None
    cwd: str | None = None
    python: str = "python3"
    interactive_ssh: bool = False
    launch_label: str | None = None
    count_in_total: bool = True


WORKERS = [
    Worker("macmini", "data/player_work_shards/elo_macmini.sqlite3", "data/logs/elo_macmini.pid", "data/logs/elo_macmini_batches.pid", launch_label="su.llb.elo.macmini"),
    Worker("imac", "data/player_work_shards/elo_imac.sqlite3", "data/logs/elo_imac.pid", ssh="ser@sers-iMac.local", cwd="~/llb_mobile_scraper"),
    Worker("oldmac", "data/player_work_shards/elo_oldmac.sqlite3", "data/logs/elo_oldmac.pid", ssh="ser@192.168.0.114", cwd="~/llb_mobile_scraper", python="/Library/Frameworks/Python.framework/Versions/3.9/bin/python3"),
    Worker("avert", "data/player_work_shards/elo_avert.sqlite3", "data/logs/elo_avert.pid", ssh="sergann@avert.local", cwd="~/llb_mobile_scraper", python="/usr/local/bin/python3"),
    Worker("yandex", "data/player_work_shards/elo_yandex.sqlite3", "data/logs/elo_yandex.pid", ssh="sergannn@81.26.187.108", cwd="~/llb_mobile_scraper"),
    Worker("postagents", "data/player_work_shards/elo_postagents.sqlite3", "data/logs/elo_postagents.pid", ssh="root@77.222.46.176", cwd="/root/llb_mobile_scraper"),
    Worker("panfilius", "data/player_work_shards/elo_panfilius.sqlite3", "data/logs/elo_panfilius.pid", ssh="root@77.222.47.218", cwd="/root/llb_mobile_scraper"),
    Worker("liza", "data/player_work_shards/elo_liza.sqlite3", "data/logs/elo_liza.pid", ssh="ubuntu@46.226.106.210", cwd="~/llb_mobile_scraper"),
    Worker("liza-extra", "data/player_work_shards/elo_liza_extra.sqlite3", "data/logs/elo_liza_extra.pid", ssh="ubuntu@46.226.106.210", cwd="~/llb_mobile_scraper", count_in_total=False),
    Worker("macmini-help", "data/player_work_shards/helpers/elo_macmini-help.sqlite3", "data/logs/elo_macmini-help.pid", count_in_total=False),
    Worker("oldmac-help", "data/player_work_shards/helpers/elo_oldmac-help.sqlite3", "data/logs/elo_oldmac-help.pid", ssh="ser@192.168.0.114", cwd="~/llb_mobile_scraper", python="/Library/Frameworks/Python.framework/Versions/3.9/bin/python3", count_in_total=False),
    Worker("yandex-help", "data/player_work_shards/helpers/elo_yandex-help.sqlite3", "data/logs/elo_yandex-help.pid", ssh="sergannn@81.26.187.108", cwd="~/llb_mobile_scraper", count_in_total=False),
    Worker("postagents-help", "data/player_work_shards/helpers/elo_postagents-help.sqlite3", "data/logs/elo_postagents-help.pid", ssh="root@77.222.46.176", cwd="/root/llb_mobile_scraper", count_in_total=False),
    Worker("panfilius-help", "data/player_work_shards/helpers/elo_panfilius-help.sqlite3", "data/logs/elo_panfilius-help.pid", ssh="root@77.222.47.218", cwd="/root/llb_mobile_scraper", count_in_total=False),
    Worker("liza-help", "data/player_work_shards/helpers/elo_liza-help.sqlite3", "data/logs/elo_liza-help.pid", ssh="ubuntu@46.226.106.210", cwd="~/llb_mobile_scraper", count_in_total=False),
    Worker("timeweb", "data/player_work_shards/elo_timeweb.sqlite3", "data/logs/elo_timeweb.pid", ssh="eco27@vh436.timeweb.ru", cwd="~/llb_mobile_scraper_elo", interactive_ssh=True),
]


REMOTE_SCRIPT = r"""
import json, os, sqlite3, subprocess
db = {db!r}
pid_path = {pid!r}
out = {{"ok": True, "pid_alive": False, "pid": None, "error": None}}
try:
    con = sqlite3.connect(db)
    cur = con.cursor()
    out["done"] = cur.execute("select count(*) from players where detail_fetched_at is not null").fetchone()[0]
    out["total"] = cur.execute("select count(*) from players").fetchone()[0]
    out["elo_players"] = cur.execute("select count(distinct player_id) from player_ratings").fetchone()[0]
    out["elo_rows"] = cur.execute("select count(*) from player_ratings").fetchone()[0]
    con.close()
    try:
        with open(pid_path) as fh:
            pid = fh.read().strip()
        out["pid"] = pid
        if pid:
            result = subprocess.run(["ps", "-p", pid, "-o", "pid="], capture_output=True, text=True)
            out["pid_alive"] = result.returncode == 0 and bool(result.stdout.strip())
    except Exception as exc:
        out["pid_error"] = str(exc)
except Exception as exc:
    out["ok"] = False
    out["error"] = str(exc)
print(json.dumps(out, ensure_ascii=False))
"""


def run_command(command: list[str], timeout: int) -> tuple[int, str, str]:
    try:
        result = subprocess.run(
            command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired as exc:
        return 124, exc.stdout or "", f"timeout after {timeout}s"


def local_status(worker: Worker) -> dict[str, object]:
    db_path = ROOT / worker.db_path
    out: dict[str, object] = {"ok": True, "pid_alive": False, "pid": None}
    try:
        con = sqlite3.connect(db_path)
        cur = con.cursor()
        out["done"] = cur.execute(
            "select count(*) from players where detail_fetched_at is not null"
        ).fetchone()[0]
        out["total"] = cur.execute("select count(*) from players").fetchone()[0]
        out["elo_players"] = cur.execute(
            "select count(distinct player_id) from player_ratings"
        ).fetchone()[0]
        out["elo_rows"] = cur.execute("select count(*) from player_ratings").fetchone()[0]
        con.close()
        if worker.launch_label:
            uid = str(os.getuid())
            code, stdout, _ = run_command(
                ["launchctl", "print", f"gui/{uid}/{worker.launch_label}"],
                3,
            )
            if code == 0 and "state = running" in stdout:
                out["pid_alive"] = True
                match = re.search(r"\n\s*pid = (\d+)", stdout)
                out["pid"] = match.group(1) if match else "launchd"
                return out

        pid_file = ROOT / worker.pid_path
        alt_pid_file = ROOT / worker.alt_pid_path if worker.alt_pid_path else None
        if alt_pid_file and alt_pid_file.exists():
            pid_file = alt_pid_file
        if pid_file.exists():
            pid = pid_file.read_text().strip()
            out["pid"] = pid
            if pid:
                code, stdout, _ = run_command(["ps", "-p", pid, "-o", "pid="], 3)
                out["pid_alive"] = code == 0 and bool(stdout.strip())
    except Exception as exc:
        out["ok"] = False
        out["error"] = str(exc)
    return out


def remote_status(worker: Worker, timeout: int) -> dict[str, object]:
    script = REMOTE_SCRIPT.format(db=worker.db_path, pid=worker.pid_path)
    command = f"cd {worker.cwd} && {worker.python} - <<'PY'\n{script}\nPY"
    ssh_command = ["ssh"]
    if worker.interactive_ssh:
        ssh_command.append("-tt")
    ssh_command += [worker.ssh or "", command]
    code, stdout, stderr = run_command(ssh_command, timeout)
    if code != 0:
        return {"ok": False, "error": stderr or stdout or f"ssh exit {code}"}
    line = stdout.splitlines()[-1] if stdout else ""
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        return {"ok": False, "error": stdout[-500:] or "empty ssh output"}


def format_row(name: str, status: dict[str, object]) -> str:
    if not status.get("ok"):
        return f"{name:10} ERROR  {status.get('error', '')}"
    done = int(status.get("done", 0))
    total = int(status.get("total", 0))
    percent = done / total * 100 if total else 0
    elo = int(status.get("elo_players", 0))
    pid = status.get("pid") or "-"
    alive = "live" if status.get("pid_alive") else "dead"
    return f"{name:10} {done:5}/{total:<5} {percent:5.1f}%  elo={elo:<5} {alive:4} pid={pid}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=int, default=25)
    args = parser.parse_args()

    rows: list[tuple[str, dict[str, object]]] = []
    for worker in WORKERS:
        status = local_status(worker) if worker.ssh is None else remote_status(worker, args.timeout)
        rows.append((worker.name, status))

    total_done = 0
    total = 0
    print("LLB ELO workers")
    print("-" * 74)
    by_name = {worker.name: worker for worker in WORKERS}
    for name, status in rows:
        print(format_row(name, status))
        if status.get("ok") and by_name[name].count_in_total:
            total_done += int(status.get("done", 0))
            total += int(status.get("total", 0))
    print("-" * 74)
    percent = total_done / total * 100 if total else 0
    remaining = total - total_done
    print(f"TOTAL      {total_done:5}/{total:<5} {percent:5.1f}%  remaining={remaining}")
    if any(not status.get("ok") for _, status in rows):
        print("Note: TOTAL includes only workers that answered.")
    if any(not by_name[name].count_in_total for name, _ in rows):
        print("Note: *-help/liza-extra are duplicate helper shards and are not included in TOTAL.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
