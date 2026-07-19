#!/usr/bin/env python3
"""Small SSH coordinator for LLB scraper shards."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def run(cmd: list[str], cwd: Path = ROOT) -> None:
    print("+ " + " ".join(shlex.quote(mask_secret(part)) for part in cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)


def shell_quote(value: str) -> str:
    return shlex.quote(value)


def mask_secret(value: str) -> str:
    password = os.environ.get("LLB_PASSWORD")
    if password:
        return value.replace(password, "***")
    return value


def remote_path(value: str) -> str:
    if value.startswith("~/") or value.startswith("$HOME/"):
        return value
    return shell_quote(value)


def worker_command(worker: dict[str, object], sleep: float) -> str:
    env_parts = []
    for key in ("LLB_USERNAME", "LLB_PASSWORD"):
        value = os.environ.get(key)
        if value:
            env_parts.append(f"{key}={shell_quote(value)}")
    args = [
        "python3",
        "tools/llb_scraper/llb_scraper.py",
        "--login",
        "--sleep",
        str(sleep),
        "--db",
        str(worker["db"]),
        "shard",
        "--player-start-page",
        str(worker["player_start_page"]),
        "--tournament-start-page",
        str(worker["tournament_start_page"]),
    ]
    optional_pairs = [
        ("player_pages", "--player-pages"),
        ("player_details", "--player-details"),
        ("tournament_pages", "--tournament-pages"),
        ("tournament_details", "--tournament-details"),
        ("competitions", "--competitions"),
    ]
    for key, flag in optional_pairs:
        value = worker.get(key)
        if value is not None:
            args.extend([flag, str(value)])
    command = " ".join(shell_quote(arg) for arg in args)
    if env_parts:
        command = " ".join(env_parts) + " " + command
    return command


def deploy(config: dict[str, object]) -> None:
    remote_dir = str(config["remote_dir"])
    for worker in config["workers"]:
        ssh = worker.get("ssh")
        if not ssh:
            continue
        run(["ssh", str(ssh), f"mkdir -p {remote_path(remote_dir)}"])
        run(
            [
                "rsync",
                "-az",
                "--delete",
                "--exclude",
                "build",
                "--exclude",
                ".dart_tool",
                "--exclude",
                "data/*.sqlite3*",
                "--exclude",
                "data/*cookies*.txt",
                "--exclude",
                "data/logs/",
                str(ROOT) + "/",
                f"{ssh}:{remote_dir}/",
            ]
        )


def check(config: dict[str, object]) -> None:
    failed = 0
    for worker in config["workers"]:
        ssh = worker.get("ssh")
        name = worker["name"]
        command = "command -v python3 && python3 --version && command -v sqlite3"
        print(f"== {name} ==", flush=True)
        cmd = ["ssh", str(ssh), command] if ssh else ["bash", "-lc", command]
        result = subprocess.run(cmd, cwd=ROOT)
        if result.returncode != 0:
            failed += 1
            print(f"!! {name} failed check", flush=True)
    if failed:
        raise SystemExit(f"{failed} worker(s) failed check")


def run_workers(config: dict[str, object], sleep: float) -> None:
    remote_dir = str(config["remote_dir"])
    processes: list[subprocess.Popen[bytes]] = []
    for worker in config["workers"]:
        ssh = worker.get("ssh")
        command = worker_command(worker, sleep)
        if ssh:
            command = f"cd {remote_path(remote_dir)} && {command}"
            cmd = ["ssh", str(ssh), command]
        else:
            cmd = ["bash", "-lc", command]
        print("+ " + " ".join(shlex.quote(mask_secret(part)) for part in cmd), flush=True)
        processes.append(subprocess.Popen(cmd, cwd=ROOT))
    failed = 0
    for process in processes:
        failed += 0 if process.wait() == 0 else 1
    if failed:
        raise SystemExit(f"{failed} worker(s) failed")


def start_workers(config: dict[str, object], sleep: float) -> None:
    remote_dir = str(config["remote_dir"])
    for worker in config["workers"]:
        name = str(worker["name"])
        ssh = worker.get("ssh")
        command = worker_command(worker, sleep)
        launch = (
            "mkdir -p data/logs; "
            f"nohup {command} > data/logs/{shell_quote(name)}.log 2>&1 & "
            "pid=$!; "
            f"echo $pid > data/logs/{shell_quote(name)}.pid; "
            f"echo started {shell_quote(name)} pid=$pid"
        )
        if ssh:
            launch = f"cd {remote_path(remote_dir)} && {launch}"
            cmd = ["ssh", str(ssh), launch]
        else:
            cmd = ["bash", "-lc", launch]
        run(cmd)


def status_workers(config: dict[str, object]) -> None:
    remote_dir = str(config["remote_dir"])
    for worker in config["workers"]:
        name = str(worker["name"])
        ssh = worker.get("ssh")
        script = (
            f"pid_file=data/logs/{shell_quote(name)}.pid; "
            f"log_file=data/logs/{shell_quote(name)}.log; "
            "if [ -f \"$pid_file\" ]; then pid=$(cat \"$pid_file\"); "
            "if kill -0 \"$pid\" 2>/dev/null; then state=running; else state=stopped; fi; "
            "else pid=''; state=no-pid; fi; "
            f"echo '== {shell_quote(name)} ==' pid=$pid state=$state; "
            "if [ -f \"$log_file\" ]; then tail -n 12 \"$log_file\"; fi"
        )
        if ssh:
            script = f"cd {remote_path(remote_dir)} && {script}"
            cmd = ["ssh", str(ssh), script]
        else:
            cmd = ["bash", "-lc", script]
        subprocess.run(cmd, cwd=ROOT)


def pull(config: dict[str, object], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    remote_dir = str(config["remote_dir"])
    for worker in config["workers"]:
        ssh = worker.get("ssh")
        db_path = str(worker["db"])
        target = output_dir / f"{worker['name']}.sqlite3"
        if ssh:
            run(["rsync", "-az", f"{ssh}:{remote_dir}/{db_path}", str(target)])
        else:
            run(["cp", str(ROOT / db_path), str(target)])


def merge(master_db: Path, shards_dir: Path) -> None:
    shards = sorted(str(path) for path in shards_dir.glob("*.sqlite3"))
    if not shards:
        raise SystemExit(f"No shards found in {shards_dir}")
    run(["python3", "tools/llb_scraper/llb_scraper.py", "--db", str(master_db), "merge", *shards])


def main() -> int:
    parser = argparse.ArgumentParser(description="Coordinate LLB scraper shards over SSH.")
    parser.add_argument("--config", default="tools/llb_scraper/distributed.example.json")
    parser.add_argument("--sleep", type=float, default=0.35)
    parser.add_argument("--shards-dir", default="data/shards")
    parser.add_argument("--master-db", default="data/llb.sqlite3")
    parser.add_argument("action", choices=["check", "deploy", "run", "start", "status", "pull", "merge", "all"])
    args = parser.parse_args()

    config = json.loads((ROOT / args.config).read_text(encoding="utf-8"))
    if args.action in {"check", "all"}:
        check(config)
    if args.action in {"deploy", "all"}:
        deploy(config)
    if args.action in {"run", "all"}:
        run_workers(config, args.sleep)
    if args.action == "start":
        start_workers(config, args.sleep)
    if args.action == "status":
        status_workers(config)
    if args.action in {"pull", "all"}:
        pull(config, ROOT / args.shards_dir)
    if args.action in {"merge", "all"}:
        merge(ROOT / args.master_db, ROOT / args.shards_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
