#!/usr/bin/env python3
"""Build a vX.Y.Z release ZIP whose manifest matches the ZIP bytes exactly.

The ZIP is assembled from the working-tree bytes, not from ``git archive``.
This avoids Git's CRLF export conversion changing file sizes after the
manifest was generated.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import update_core

ROOT = Path(__file__).resolve().parent.parent


def load_baseline_core(path: Path):
    """Load the updater currently installed on the target machine."""
    spec = importlib.util.spec_from_file_location("_installed_update_core", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load installed updater: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def tracked_files() -> list[str]:
    raw = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "-z"])
    return [item.decode("utf-8") for item in raw.split(b"\0") if item]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--baseline-core",
        default="",
        help=(
            "Installed updater to test archive compatibility against. "
            "Defaults to ../tools/update_core.py when it exists."
        ),
    )
    args = parser.parse_args()
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if not update_core.VERSION_RE.fullmatch(version):
        raise SystemExit(f"invalid VERSION: {version!r}")
    output = ROOT.parent / f"public-release-v{version}.zip"
    entries: list[tuple[str, bytes]] = []
    manifest_files: list[dict] = []
    for rel in tracked_files():
        if rel == "update-manifest.json":
            continue
        path = ROOT / rel
        if not path.is_file():
            raise SystemExit(f"tracked file missing from worktree: {rel}")
        data = path.read_bytes()
        entries.append((rel, data))
        if update_core.is_allowed_path(rel):
            manifest_files.append(
                {
                    "path": rel,
                    "size": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
            )
    rejected_self = [
        rel
        for rel, _ in entries
        if rel != "update-manifest.json" and not update_core.is_allowed_path(rel)
    ]
    if rejected_self:
        raise SystemExit(
            "package contains paths rejected by its own updater: "
            + ", ".join(rejected_self)
        )

    baseline_core = args.baseline_core or str(ROOT.parent / "tools" / "update_core.py")
    baseline_path = Path(baseline_core)
    if (
        baseline_path.is_file()
        and baseline_path.resolve() != (ROOT / "tools" / "update_core.py").resolve()
    ):
        installed_core = load_baseline_core(baseline_path)
        rejected_installed = [
            rel
            for rel, _ in entries
            if rel != "update-manifest.json" and not installed_core.is_allowed_path(rel)
        ]
        if rejected_installed:
            raise SystemExit(
                "installed updater rejects package paths (patch it before "
                "packaging): " + ", ".join(rejected_installed)
            )
        print(f"compat check OK against {baseline_path}")

    manifest_files.sort(key=lambda item: item["path"])
    manifest = update_core.validate_manifest(
        {"schema": 1, "version": version, "files": manifest_files}
    )
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode(
        "utf-8"
    )
    (ROOT / "update-manifest.json").write_bytes(manifest_bytes)

    temporary = ROOT.parent / (output.name + ".tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for rel, data in entries:
            archive.writestr(rel, data)
        archive.writestr("update-manifest.json", manifest_bytes)
    temporary.replace(output)

    # Re-open the final bytes and prove that the manifest hashes match.
    with tempfile.TemporaryDirectory(prefix="cyber-butler-package-") as temp:
        extracted = Path(temp) / "extracted"
        parsed = update_core.extract_zip(output, extracted)
        if parsed["version"] != version:
            raise SystemExit("manifest version changed during packaging")
        for entry in parsed["files"]:
            data = (extracted / Path(entry["path"])).read_bytes()
            if len(data) != entry["size"]:
                raise SystemExit(f"packaged size mismatch: {entry['path']}")
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise SystemExit(f"packaged hash mismatch: {entry['path']}")

    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print(f"wrote {output}")
    print(
        f"version={version} files={len(manifest['files'])} bytes={output.stat().st_size}"
    )
    print(f"sha256={digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
