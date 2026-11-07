#!/usr/bin/env python3
"""Rewrite a wheel with deterministic ZIP metadata for reproducible builds."""
from __future__ import annotations

import argparse
import zipfile
from pathlib import Path

FIXED_TIME = (1980, 1, 1, 0, 0, 0)


def normalize(path: Path) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with zipfile.ZipFile(path) as source, zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as target:
        for name in sorted(source.namelist()):
            data = source.read(name)
            info = zipfile.ZipInfo(name, date_time=FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            info.create_system = 0
            target.writestr(info, data)
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("wheels", nargs="+")
    args = parser.parse_args()
    for name in args.wheels:
        normalize(Path(name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
