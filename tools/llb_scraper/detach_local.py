#!/usr/bin/env python3
"""Run a local command detached, with stdout/stderr redirected to a log file."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Start a detached local scraper command.")
    parser.add_argument("--log", required=True)
    parser.add_argument("--pid", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command:
        raise SystemExit("command is required")
    log_path = Path(args.log)
    pid_path = Path(args.pid)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    pid_path.parent.mkdir(parents=True, exist_ok=True)
    log_file = log_path.open("ab", buffering=0)
    process = subprocess.Popen(
        args.command,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL,
        start_new_session=True,
    )
    pid_path.write_text(str(process.pid) + "\n", encoding="utf-8")
    print(f"started pid={process.pid} log={log_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
