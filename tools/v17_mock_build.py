#!/usr/bin/env python3
"""Create a deterministic mock artifact for the reusable workflow harness."""
from __future__ import annotations
import argparse, hashlib
from pathlib import Path


def main() -> int:
    """Run the mock build CLI."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="dist")
    parser.add_argument("--version", default="1.7.0")
    args = parser.parse_args()
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    wheel = out / f"mock_cbs-{args.version}-py3-none-any.whl"
    wheel.write_bytes(f"mock wheel {args.version}".encode())
    digest = hashlib.sha256(wheel.read_bytes()).hexdigest()
    (out / "WHEEL_SHA256").write_text(f"{digest}  {wheel.name}\n", encoding="utf-8")
    (out / "RELEASE_ASSETS.sha256").write_text(
        f"{digest}  {wheel.name}\n", encoding="utf-8")
    print("MOCK_ARTIFACT_CREATED", wheel)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
