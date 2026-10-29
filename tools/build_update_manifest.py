#!/usr/bin/env python3
"""Deprecated standalone manifest builder.

Use :mod:`tools.package_release` for release packaging: it hashes the same
working-tree bytes that it writes into the final ZIP, so Git CRLF conversion
cannot make the manifest disagree with the archive.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import update_core


def collect(root: Path) -> list[dict]:
    files: list[dict] = []
    for base in ("tools", "plugins", "overlay", "docs"):
        for path in sorted((root / base).rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(root).as_posix()
            if not update_core.is_allowed_path(rel):
                continue
            data = path.read_bytes()
            files.append(
                {
                    "path": rel,
                    "size": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
            )
    for name in (
        "VERSION",
        "README.md",
        "README_en.md",
        "README_zh.md",
        "README_ja.md",
        "README_ko.md",
        "README_es.md",
        "README_fr.md",
        "README_de.md",
        "README_ru.md",
        "SECURITY.md",
        "LICENSE",
    ):
        path = root / name
        if path.is_file():
            data = path.read_bytes()
            files.append(
                {
                    "path": name,
                    "size": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
            )
    files.sort(key=lambda item: item["path"])
    if len(files) != len({item["path"] for item in files}):
        raise SystemExit("duplicate manifest paths")
    return files


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    manifest = {"schema": 1, "version": version, "files": collect(root)}
    update_core.validate_manifest(manifest)
    out = root / "update-manifest.json"
    out.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {out} ({len(manifest['files'])} files, version {version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
