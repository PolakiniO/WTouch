#!/usr/bin/env python3
"""Embed the workflow GIF directly into the README via a data URI."""
from __future__ import annotations

import argparse
import base64
from pathlib import Path

DATA_URI_PREFIX = "data:image/gif;base64,"
ALT_SNIPPET = "\" alt=\"Animated walkthrough of wtouch usage showing key commands and workflow\" />"

def update_readme(readme_path: Path, encoded: str) -> None:
    text = readme_path.read_text()
    marker = DATA_URI_PREFIX
    try:
        start = text.index(marker) + len(marker)
    except ValueError as exc:
        raise SystemExit("Existing data URI not found in README") from exc

    try:
        end = text.index('" alt="Animated walkthrough of wtouch usage showing key commands and workflow" />', start)
    except ValueError as exc:
        raise SystemExit("Could not locate end of existing data URI block") from exc

    new_text = text[:start] + encoded + text[end:]
    readme_path.write_text(new_text)


def encode_gif(path: Path) -> str:
    data = path.read_bytes()
    return base64.b64encode(data).decode("ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gif", type=Path, help="Path to the workflow GIF to embed")
    parser.add_argument("--readme", type=Path, default=Path("README.md"), help="README file to update (default: README.md)")
    args = parser.parse_args()

    if not args.gif.is_file():
        raise SystemExit(f"GIF '{args.gif}' not found")

    encoded = encode_gif(args.gif)
    update_readme(args.readme, encoded)
    print(f"Embedded {args.gif} into {args.readme} ({len(encoded)} base64 chars)")


if __name__ == "__main__":
    main()
