#!/usr/bin/env python3
"""Stamp coverage.json with the SHA256 of the measured source files."""
from __future__ import annotations

import argparse
from pathlib import Path

from cbp.source_hash import stamp


def main() -> int:
    parser = argparse.ArgumentParser(prog="stamp-coverage")
    parser.add_argument("--coverage", default="coverage.json")
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    root = Path(args.root)
    value = stamp(Path(args.coverage), root)
    print("COVERAGE_SOURCE_HASH=" + value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
