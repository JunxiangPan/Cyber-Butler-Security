#!/usr/bin/env python3
"""Generate file-count benchmark timings for the custom-rule scanner."""
from __future__ import annotations

import argparse
import json
import tempfile
import time
from pathlib import Path

from cbp import custom_rules
from cbp.config import GateConfig


def run(count: int) -> float:
    with tempfile.TemporaryDirectory(prefix="cbp-bench-") as temp:
        root = Path(temp)
        for index in range(count):
            (root / f"f{index}.py").write_text("print('ok')\n", encoding="utf-8")
        cfg = GateConfig(root=root, custom_rules=({
            "name": "bench", "pattern": "print", "files": ["*.py"],
            "message": "hit", "mode": "warn", "max_matches": 1,
        },))
        started = time.perf_counter()
        custom_rules.run(cfg)
        return time.perf_counter() - started


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--counts", default="1000,5000,20000")
    args = parser.parse_args()
    result = {str(count): run(int(count)) for count in args.counts.split(",")}
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
