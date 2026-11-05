#!/usr/bin/env python3
"""Require provenance for large binaries shipped in the release package.

Any .exe/.dll/.bin larger than 5 MiB must have a matching build record and
SBOM under artifacts/. This turns a large black-box binary into a documented
and reproducible build artifact.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 5 * 1024 * 1024


def _discover(package: Path, root: Path) -> list[tuple[str, int, bytes]]:
    if package.is_file():
        with zipfile.ZipFile(package) as archive:
            return [
                (name, info_size(archive, name), archive.read(name))
                for name in archive.namelist()
                if name.lower().endswith((".exe", ".dll", ".bin"))
                and info_size(archive, name) > LIMIT
            ]
    found = []
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".exe", ".dll", ".bin"} and path.stat().st_size > LIMIT:
            if not any(part in {".git", ".venv", "__pycache__"} for part in path.parts) and "build/bin" not in path.as_posix() and "build/obj" not in path.as_posix() and "build/publish" not in path.as_posix():
                found.append((path.relative_to(root).as_posix(), path.stat().st_size, path.read_bytes()))
    return found


def info_size(archive: zipfile.ZipFile, name: str) -> int:
    return archive.getinfo(name).file_size


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", default=str(ROOT.parent / "public-release-v1.6.3.zip"))
    parser.add_argument("--artifacts", default=str(ROOT / "artifacts"))
    args = parser.parse_args()
    package = Path(args.package)
    artifacts = Path(args.artifacts)
    candidates = _discover(package, ROOT)
    if not candidates:
        print("BINARY_PROVENANCE_OK: no binary over 5 MiB in the checked tree")
        return 0
    failed = False
    for name, size, data in candidates:
        base = Path(name).name
        build = artifacts / (base + ".build.json")
        sbom = artifacts / (base + ".sbom.json")
        if not build.is_file() or not sbom.is_file():
            print(f"BINARY_PROVENANCE_FAILED: {name} is {size} bytes and lacks {base}.build.json/.sbom.json")
            failed = True
            continue
        record = json.loads(build.read_text(encoding="utf-8"))
        digest = hashlib.sha256(data).hexdigest().upper()
        if record.get("sha256", "").upper() != digest or int(record.get("size_bytes", -1)) != size:
            print(f"BINARY_PROVENANCE_FAILED: {name} provenance hash/size mismatch")
            failed = True
            continue
        if not record.get("build", {}).get("command"):
            print(f"BINARY_PROVENANCE_FAILED: {name} has no build command")
            failed = True
        if not json.loads(sbom.read_text(encoding="utf-8")).get("components"):
            print(f"BINARY_PROVENANCE_FAILED: {name} SBOM has no components")
            failed = True
    if failed:
        return 1
    print(f"BINARY_PROVENANCE_OK: {len(candidates)} large binaries have build records and SBOMs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
