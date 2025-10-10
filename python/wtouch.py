#!/usr/bin/env python3
"""Cross-platform Python implementation of wtouch."""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import sys
from typing import Iterable, Optional, Tuple


def parse_datetime(value: str) -> float:
    formats = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
    ]
    for fmt in formats:
        try:
            parsed = _dt.datetime.strptime(value, fmt)
            return parsed.timestamp()
        except ValueError:
            continue
    raise argparse.ArgumentTypeError(
        "expected YYYY-MM-DD, YYYY-MM-DD HH:MM, or YYYY-MM-DD HH:MM:SS"
    )


def parse_touch_timestamp(value: str) -> float:
    if "." in value:
        main, fraction = value.split(".", 1)
        if len(fraction) != 2 or not fraction.isdigit():
            raise argparse.ArgumentTypeError("seconds fraction must have two digits")
        seconds = int(fraction)
    else:
        main, seconds = value, 0

    if len(main) not in (8, 10, 12) or not main.isdigit():
        raise argparse.ArgumentTypeError(
            "expected [[CC]YY]MMDDhhmm with optional .ss suffix"
        )

    now = _dt.datetime.now()
    idx = len(main)

    def take(length: int) -> int:
        nonlocal idx
        if idx < length:
            raise argparse.ArgumentTypeError("invalid timestamp format")
        start = idx - length
        idx -= length
        return int(main[start: start + length])

    minute = take(2)
    hour = take(2)
    day = take(2)
    month = take(2)

    if idx == 0:
        year = now.year
    elif idx == 2:
        year = (now.year // 100) * 100 + int(main[:2])
    elif idx == 4:
        year = int(main[:4])
    else:
        raise argparse.ArgumentTypeError("invalid timestamp length")

    try:
        parsed = _dt.datetime(year, month, day, hour, minute, seconds)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc

    return parsed.timestamp()


def load_reference_times(path: str) -> Tuple[float, float]:
    stats = os.stat(path)
    return stats.st_atime, stats.st_mtime


def ensure_exists(path: str) -> None:
    if os.path.exists(path):
        return
    parent = os.path.dirname(path)
    if parent and not os.path.exists(parent):
        raise FileNotFoundError(f"directory does not exist: {parent}")
    with open(path, "a", encoding="utf-8"):
        pass


def apply_times(
    path: str,
    atime: Optional[float],
    mtime: Optional[float],
    touch_access: bool,
    touch_modify: bool,
) -> None:
    stats = os.stat(path)
    current_atime = stats.st_atime
    current_mtime = stats.st_mtime

    if atime is None:
        atime = current_atime
    if mtime is None:
        mtime = current_mtime

    if touch_access and not touch_modify:
        mtime = current_mtime
    if touch_modify and not touch_access:
        atime = current_atime

    os.utime(path, (atime, mtime))


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="wtouch.py")
    parser.add_argument("paths", nargs="+", help="Files or directories to update")
    parser.add_argument("-a", dest="touch_access", action="store_true", help="Change the access time only")
    parser.add_argument("-m", dest="touch_modify", action="store_true", help="Change the modification time only")
    parser.add_argument(
        "-c",
        "--no-create",
        dest="no_create",
        action="store_true",
        help="Do not create files that do not exist",
    )
    parser.add_argument(
        "-d",
        dest="date_string",
        help="Explicit timestamp in YYYY-MM-DD[ HH:MM[:SS]] format",
    )
    parser.add_argument(
        "-t",
        dest="timestamp_string",
        help="Timestamp in [[CC]YY]MMDDhhmm[.ss] format",
    )
    parser.add_argument(
        "-r",
        dest="reference",
        help="Copy timestamps from another path",
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)

    explicit_sources = sum(
        1 for candidate in (args.reference, args.date_string, args.timestamp_string) if candidate
    )
    if explicit_sources > 1:
        print(
            "wtouch.py: options -r, -d and -t are mutually exclusive",
            file=sys.stderr,
        )
        return 1

    explicit_times: Optional[Tuple[float, float]] = None
    if args.reference:
        ref_atime, ref_mtime = load_reference_times(args.reference)
        explicit_times = (ref_atime, ref_mtime)
    elif args.date_string:
        timestamp = parse_datetime(args.date_string)
        explicit_times = (timestamp, timestamp)
    elif args.timestamp_string:
        timestamp = parse_touch_timestamp(args.timestamp_string)
        explicit_times = (timestamp, timestamp)

    touch_access = args.touch_access or not (args.touch_access or args.touch_modify)
    touch_modify = args.touch_modify or not (args.touch_access or args.touch_modify)

    for path in args.paths:
        try:
            if not os.path.exists(path):
                if args.no_create:
                    continue
                ensure_exists(path)
            if explicit_times:
                atime, mtime = explicit_times
            else:
                now = _dt.datetime.now().timestamp()
                atime = mtime = now
            apply_times(path, atime, mtime, touch_access, touch_modify)
        except FileNotFoundError as exc:
            print(f"wtouch.py: {exc}", file=sys.stderr)
            return 1
        except OSError as exc:
            print(f"wtouch.py: failed to update '{path}': {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
