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
        "source": requirements.name,
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


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["build", "verify"])
    parser.add_argument("--requirements", required=True)
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    if args.command == "build":
        build(Path(args.requirements), Path(args.manifest))
        print("SBOM_BUILT")
        return 0
    ok, reason = verify(Path(args.requirements), Path(args.manifest))
    print(reason)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
