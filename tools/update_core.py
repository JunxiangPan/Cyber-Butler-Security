"""Safe, dependency-free primitives for Cyber-Butler release updates.

The updater itself is deliberately small: this module validates the update
manifest, rejects every path that could touch user data, and applies only
allow-listed files. It never deletes files.

CLI:
    python tools/update_core.py extract --zip PATH --dest PATH
    python tools/update_core.py apply --staging PATH --target PATH --manifest PATH
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath

SCHEMA_VERSION = 1
MAX_FILES = 500
MAX_TOTAL_BYTES = 256 * 1024 * 1024
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+){1,3}(?:[-+][0-9A-Za-z.-]+)?$")

ALLOWED_ROOTS = ("tools/", "plugins/", "overlay/", "docs/", "tests/", "webui/", ".github/")
ALLOWED_ROOT_FILES = {
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
    ".gitignore",
    "requirements-dev.txt",
    "pytest.ini",
    "update-manifest.sig",
    "config.pro.example.json",
    "config.lite.example.json",
    "VERSION",
}
DENIED_PARTS = {
    "astrbot/data",
    "astrbot/.venv",
    "snowluma/config",
    "snowluma/logs",
    "backups",
    "data",
    "logs",
    "log",
    "node_modules",
    ".git",
    "__pycache__",
    ".venv",
    "venv",
}
SENSITIVE_BASENAMES = {
    "cmd_config.json",
    "config.json",
    ".astrbot_token",
    ".astrbot_ws_token",
    ".snowluma_token",
    "broker_token.txt",
    "totp_secret.dpapi",
    "totp_recovery.json",
    "snowluma_guard.json",
}
SENSITIVE_SUFFIXES = (
    ".db",
    ".sqlite",
    ".sqlite3",
    ".dpapi",
    ".key",
    ".pem",
    ".env",
)


class UpdateSafetyError(ValueError):
    """Raised when an update package or manifest violates the safety policy."""


def _normalise_path(value: object) -> str:
    raw = str(value or "").strip()
    if not raw or "\x00" in raw or "\\" in raw:
        raise UpdateSafetyError(f"invalid update path: {raw!r}")
    if raw.startswith("/") or re.match(r"^[A-Za-z]:", raw):
        raise UpdateSafetyError(f"absolute update path: {raw!r}")
    path = PurePosixPath(raw)
    if any(part in ("", ".", "..") for part in path.parts):
        raise UpdateSafetyError(f"path traversal in update path: {raw!r}")
    return path.as_posix()


def is_allowed_path(value: object) -> bool:
    """Return True only for a code/docs path that may be replaced."""
    try:
        path = _normalise_path(value)
    except UpdateSafetyError:
        return False
    lower = path.casefold()
    if path in ALLOWED_ROOT_FILES or lower in ALLOWED_ROOT_FILES:
        return True
    if lower.startswith("release_notes_") and lower.endswith(".md"):
        return True
    if not any(lower.startswith(root) for root in ALLOWED_ROOTS):
        return False
    parts = lower.split("/")
    if any(part in DENIED_PARTS for part in parts):
        return False
    basename = parts[-1]
    if basename in SENSITIVE_BASENAMES:
        return False
    if basename.startswith(".") or basename.startswith("config."):
        return False
    if basename.endswith(SENSITIVE_SUFFIXES):
        return False
    return True


def validate_manifest(value: object) -> dict:
    """Validate and return a canonical manifest.

    Args:
        value: Parsed JSON object from ``update-manifest.json``.

    Returns:
        A canonical manifest with sorted file entries.

    Raises:
        UpdateSafetyError: If any path, hash, size, or schema field is invalid.
    """
    if not isinstance(value, dict):
        raise UpdateSafetyError("manifest must be an object")
    if value.get("schema") != SCHEMA_VERSION:
        raise UpdateSafetyError("unsupported manifest schema")
    version = str(value.get("version", "")).strip()
    if not VERSION_RE.fullmatch(version):
        raise UpdateSafetyError("manifest version is invalid")
    files = value.get("files")
    if not isinstance(files, list) or not files:
        raise UpdateSafetyError("manifest files must be a non-empty list")
    if len(files) > MAX_FILES:
        raise UpdateSafetyError("manifest has too many files")
    seen: set[str] = set()
    canonical: list[dict] = []
    for entry in files:
        if not isinstance(entry, dict):
            raise UpdateSafetyError("manifest entry must be an object")
        path = _normalise_path(entry.get("path"))
        if path in seen:
            raise UpdateSafetyError(f"duplicate manifest path: {path}")
        if not is_allowed_path(path):
            raise UpdateSafetyError(f"manifest path is not allow-listed: {path}")
        digest = str(entry.get("sha256", "")).strip().lower()
        if not SHA256_RE.fullmatch(digest):
            raise UpdateSafetyError(f"invalid sha256 for {path}")
        try:
            size = int(entry.get("size"))
        except (TypeError, ValueError) as exc:
            raise UpdateSafetyError(f"invalid size for {path}") from exc
        if size < 0 or size > MAX_TOTAL_BYTES:
            raise UpdateSafetyError(f"invalid size for {path}")
        seen.add(path)
        canonical.append({"path": path, "sha256": digest, "size": size})
    canonical.sort(key=lambda item: item["path"])
    return {"schema": SCHEMA_VERSION, "version": version, "files": canonical}


def load_manifest(path: Path) -> dict:
    """Load and validate a manifest from disk."""
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise UpdateSafetyError(f"cannot read manifest: {exc}") from exc
    return validate_manifest(value)


def _is_symlink(info: zipfile.ZipInfo) -> bool:
    mode = (info.external_attr >> 16) & 0o170000
    return mode == stat.S_IFLNK


def extract_zip(zip_path: Path, dest: Path) -> dict:
    """Validate every member and extract a release into an empty staging dir.

    The complete archive is checked before any file is written. A single
    disallowed member rejects the whole archive, so a malicious ``data/`` file
    cannot be silently ignored.

    Args:
        zip_path: Downloaded release archive.
        dest: Destination staging directory.

    Returns:
        The validated manifest from the archive.

    Raises:
        UpdateSafetyError: On traversal, symlinks, disallowed paths, duplicate
            names, excessive size, or a missing manifest.
    """
    dest = Path(dest).resolve()
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        members = archive.infolist()
        if not members:
            raise UpdateSafetyError("release archive is empty")
        if len(members) > MAX_FILES:
            raise UpdateSafetyError("release archive has too many files")
        checked: list[tuple[zipfile.ZipInfo, Path, int]] = []
        total = 0
        seen: set[str] = set()
        for info in members:
            if info.is_dir():
                continue
            if _is_symlink(info):
                raise UpdateSafetyError(f"symlink member rejected: {info.filename}")
            name = _normalise_path(info.filename)
            if name in seen:
                raise UpdateSafetyError(f"duplicate archive member: {name}")
            seen.add(name)
            if not (is_allowed_path(name) or name == "update-manifest.json"):
                raise UpdateSafetyError(f"archive member is not allow-listed: {name}")
            total += int(info.file_size)
            if total > MAX_TOTAL_BYTES:
                raise UpdateSafetyError("release archive exceeds size limit")
            checked.append((info, dest / PurePosixPath(name), int(info.file_size)))
        for info, target, _ in checked:
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)

    manifest_path = dest / "update-manifest.json"
    return load_manifest(manifest_path)


def apply_update(staging: Path, target: Path, manifest: dict) -> list[str]:
    """Copy validated manifest files into the target tree without deleting data."""
    staging = Path(staging).resolve()
    target = Path(target).resolve()
    applied: list[str] = []
    for entry in manifest.get("files", []):
        rel = _normalise_path(entry["path"])
        if not is_allowed_path(rel):
            raise UpdateSafetyError(f"apply path is not allow-listed: {rel}")
        source = (staging / PurePosixPath(rel)).resolve()
        destination = (target / PurePosixPath(rel)).resolve()
        if not source.is_relative_to(staging) or not destination.is_relative_to(target):
            raise UpdateSafetyError(f"path escaped staging/target: {rel}")
        if not source.is_file():
            raise UpdateSafetyError(f"staged file missing: {rel}")
        data = source.read_bytes()
        if len(data) != entry["size"]:
            raise UpdateSafetyError(f"size mismatch: {rel}")
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise UpdateSafetyError(f"sha256 mismatch: {rel}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".update-new")
        shutil.copy2(source, temporary)
        temporary.replace(destination)
        applied.append(rel)
    return applied


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Cyber-Butler update safety core")
    sub = parser.add_subparsers(dest="command", required=True)
    extract = sub.add_parser("extract")
    extract.add_argument("--zip", required=True)
    extract.add_argument("--dest", required=True)
    apply_cmd = sub.add_parser("apply")
    apply_cmd.add_argument("--staging", required=True)
    apply_cmd.add_argument("--target", required=True)
    apply_cmd.add_argument("--manifest", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "extract":
            manifest = extract_zip(Path(args.zip), Path(args.dest))
            print(json.dumps(manifest, ensure_ascii=False, indent=2))
        else:
            manifest = load_manifest(Path(args.manifest))
            applied = apply_update(Path(args.staging), Path(args.target), manifest)
            print(json.dumps({"applied": applied}, ensure_ascii=True))
        return 0
    except (OSError, UpdateSafetyError, zipfile.BadZipFile) as exc:
        print(f"UPDATE_REJECTED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
