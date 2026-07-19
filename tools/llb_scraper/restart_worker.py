#!/usr/bin/env python3
"""Run a command and restart it after failures until it exits successfully."""

from __future__ import annotations

import argparse
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


def stamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def main() -> int:
    parser = argparse.ArgumentParser(description="Restart a scraper command after non-zero exits.")
    parser.add_argument("--log", required=True, help="Command stdout/stderr log.")
    parser.add_argument("--pid", required=True, help="PID file for the currently running child.")
    parser.add_argument("--watch-log", required=True, help="Watchdog event log.")
    parser.add_argument("--delay", type=float, default=10.0, help="Seconds to wait before restart.")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command:
        raise SystemExit("command is required")

    log_path = Path(args.log)
    pid_path = Path(args.pid)
    watch_log_path = Path(args.watch_log)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    pid_path.parent.mkdir(parents=True, exist_ok=True)
    watch_log_path.parent.mkdir(parents=True, exist_ok=True)

    with watch_log_path.open("a", encoding="utf-8") as watch_log:
        attempt = 0
        while True:
            attempt += 1
            watch_log.write(f"{stamp()} start attempt={attempt} command={args.command!r}\n")
            watch_log.flush()
            with log_path.open("ab", buffering=0) as log_file:
                process = subprocess.Popen(
                    args.command,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL,
                )
                pid_path.write_text(str(process.pid) + "\n", encoding="utf-8")
                return_code = process.wait()
            watch_log.write(f"{stamp()} exit attempt={attempt} returncode={return_code}\n")
            watch_log.flush()
            if return_code == 0:
                pid_path.unlink(missing_ok=True)
                watch_log.write(f"{stamp()} complete\n")
                watch_log.flush()
                return 0
            time.sleep(args.delay)


if __name__ == "__main__":
    raise SystemExit(main())
