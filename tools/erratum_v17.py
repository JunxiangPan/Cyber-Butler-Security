#!/usr/bin/env python3
"""Add the F4 machine-readable ERRATUM marker without rewriting history."""
from __future__ import annotations

import argparse
from pathlib import Path


def mark(body: str, reason: str) -> str:
    """Mark a release body as an erratum once."""
    if body.lstrip().startswith("ERRATUM:"):
        return body
    return f"ERRATUM:\n\n{reason.strip()}\n\n{body}"


def main() -> int:
    """Run the erratum CLI."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--body", required=True)
    parser.add_argument("--reason", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    text = Path(args.body).read_text(encoding="utf-8")
    Path(args.output).write_text(mark(text, args.reason), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
