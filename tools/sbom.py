"""Small SBOM/hash manifest for installer dependency files."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build(requirements: Path, output: Path | None = None) -> dict:
    requirements = Path(requirements)
    lines = [
        line.rstrip()
        for line in requirements.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    manifest = {
        "schema": 1,
        "source": str(requirements),
        "sha256": _sha256(requirements),
        "requirements": lines,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    if output is not None:
        Path(output).write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
            encoding="utf-8",
        )
    return manifest


def verify(requirements: Path, manifest: Path) -> tuple[bool, str]:
    expected = json.loads(Path(manifest).read_text(encoding="utf-8"))
    actual = build(requirements)
    if expected.get("sha256") != actual["sha256"]:
        return False, "requirements.txt hash mismatch"
    if expected.get("requirements") != actual["requirements"]:
        return False, "requirements list mismatch"
    return True, "SBOM matches requirements.txt"
