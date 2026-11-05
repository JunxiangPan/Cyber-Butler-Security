"""Small SBOM/hash manifest for installer dependency files."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def _sha256(path: Path) -> str:
    """Sha256.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build(requirements: Path, output: Path | None = None) -> dict:
    """Build.
    
    Args:
        requirements: caller-supplied value.
        output: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
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
    """Verify.
    
    Args:
        requirements: caller-supplied value.
        manifest: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    expected = json.loads(Path(manifest).read_text(encoding="utf-8"))
    actual = build(requirements)
    if expected.get("sha256") != actual["sha256"]:
        return False, "requirements.txt hash mismatch"
    if expected.get("requirements") != actual["requirements"]:
        return False, "requirements list mismatch"
    return True, "SBOM matches requirements.txt"


def build_bundle(root: Path, output: Path, manifests: list[Path] | None = None) -> dict:
    """Hash every local dependency manifest, not just one requirements file."""
    root = Path(root).resolve()
    paths = manifests or [Path("requirements-dev.txt"), Path("webui/requirements.txt")]
    entries = []
    for relative in paths:
        relative = Path(relative)
        path = (root / relative).resolve()
        if not path.is_file():
            raise FileNotFoundError(path)
        entries.append({
            "path": relative.as_posix(),
            "sha256": _sha256(path),
            "requirements": build(path)["requirements"],
        })
    manifest = {
        "schema": 2,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "entries": entries,
    }
    Path(output).write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    return manifest


def verify_bundle(root: Path, manifest_path: Path) -> tuple[bool, str]:
    """Verify bundle.
    
    Args:
        root: caller-supplied value.
        manifest_path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    root = Path(root).resolve()
    try:
        manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return False, f"cannot read bundle manifest: {exc}"
    entries = manifest.get("entries")
    if not isinstance(entries, list) or not entries:
        return False, "bundle manifest has no entries"
    for entry in entries:
        if not isinstance(entry, dict):
            return False, "invalid bundle entry"
        relative = Path(str(entry.get("path", "")))
        path = (root / relative).resolve()
        if root not in path.parents or not path.is_file():
            return False, f"missing or escaped dependency manifest: {relative}"
        actual = build(path)
        if actual["sha256"] != entry.get("sha256") or actual["requirements"] != entry.get("requirements"):
            return False, f"dependency manifest changed: {relative}"
    return True, f"SBOM bundle matches {len(entries)} dependency manifests"


def build_default_bundle(root: Path, output: Path) -> dict:
    """Build default bundle.
    
    Args:
        root: caller-supplied value.
        output: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return build_bundle(root, output)


def main() -> int:
    """Main.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["build", "verify", "build-bundle", "verify-bundle"])
    parser.add_argument("--requirements")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    if args.command in {"build", "verify"}:
        if not args.requirements:
            print("--requirements is required")
            return 2
        if args.command == "build":
            build(Path(args.requirements), Path(args.manifest))
            print("SBOM_BUILT")
            return 0
        ok, reason = verify(Path(args.requirements), Path(args.manifest))
    elif args.command == "build-bundle":
        build_bundle(Path(args.root), Path(args.manifest))
        print("SBOM_BUNDLE_BUILT")
        return 0
    else:
        ok, reason = verify_bundle(Path(args.root), Path(args.manifest))
    print(reason)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
