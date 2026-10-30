"""Production overlay and rendering helpers for update_merge.ps1.

The public release contains placeholders such as YOUR_PROJECT_PATH. This module
keeps deployment values in a local overlay, renders only runtime files, and
builds a second manifest containing the rendered hashes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import re
import sys
import time
from pathlib import Path

import update_core

OVERLAY_SCHEMA = 1
PLACEHOLDER_RE = re.compile(r"YOUR_[A-Z0-9_]+")
RUNTIME_EXCLUDED = {
    "tools/build_update_manifest.py",
    "tools/package_release.py",
    "tools/sanitize_for_release.py",
    "tools/update_core.py",
    "tools/update_merge_core.py",
    "tools/update_merge.ps1",
    "tools/update.ps1",
    "tools/check_update.ps1",
}
RUNTIME_EXACT = {
    "tools/broker.py",
    "tools/snowluma_guard.py",
    "plugins/astrbot_plugin_security_gate/main.py",
    "plugins/astrbot_plugin_totp_broker/main.py",
    "plugins/astrbot_plugin_cloud_fallback/main.py",
}
RUNTIME_PREFIXES = ("overlay/", "tools/")
PROTECTED_PARTS = {
    "astrbot/data",
    "snowluma/config",
    "backups",
    ".venv",
    "logs",
}
PROTECTED_EXACT = {
    "astrbot/data/cmd_config.json",
    "tools/broker_token.txt",
    "tools/totp_secret.dpapi",
    "tools/totp_recovery.json",
    ".astrbot_token",
    ".astrbot_ws_token",
    ".snowluma_token",
    "local-overlay.json",
}
TEXT_SUFFIXES = {".py", ".ps1", ".psm1", ".vbs", ".bat", ".cmd"}
OVERLAY_TARGETS = (
    ("overlay/astrbot/core/", "AstrBot/astrbot/core/"),
    ("overlay/astrbot/dashboard/", "AstrBot/astrbot/dashboard/"),
    ("overlay/astrbot/data/plugins/", "AstrBot/data/plugins/"),
)
OVERLAY_TARGET_PREFIXES = tuple(target for _, target in OVERLAY_TARGETS)
logger = logging.getLogger(__name__)


class MergeError(ValueError):
    """Raised when rendering or overlay validation is unsafe."""


def _norm(path: object) -> str:
    return update_core._normalise_path(path)


def is_protected(path: object) -> bool:
    try:
        value = _norm(path).casefold()
    except update_core.UpdateSafetyError:
        return True
    if value in PROTECTED_EXACT:
        return True
    if value.startswith(("astrbot/data/", "snowluma/config/")):
        return True
    parts = value.split("/")
    if any(part in PROTECTED_PARTS for part in parts):
        return True
    return value.endswith((".db", ".sqlite", ".sqlite3", ".dpapi", ".token"))


def is_runtime(path: object) -> bool:
    try:
        value = _norm(path)
    except update_core.UpdateSafetyError:
        return False
    if value in RUNTIME_EXCLUDED:
        return False
    if value in RUNTIME_EXACT:
        return True
    if any(value.startswith(prefix) for prefix in OVERLAY_TARGET_PREFIXES):
        return Path(value).suffix.casefold() in TEXT_SUFFIXES
    if any(value.startswith(prefix) for prefix in RUNTIME_PREFIXES):
        return Path(value).suffix.casefold() in TEXT_SUFFIXES
    return False


def validate_manifest_protected(manifest: dict) -> None:
    for entry in manifest.get("files", []):
        if is_protected(entry["path"]):
            raise MergeError(f"manifest contains protected path: {entry['path']}")


def load_overlay(path: Path) -> dict:
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise MergeError(f"cannot read local overlay: {exc}") from exc
    if not isinstance(value, dict) or value.get("schema") != OVERLAY_SCHEMA:
        raise MergeError("invalid local-overlay schema")
    values = value.get("values")
    if not isinstance(values, dict) or not values:
        raise MergeError("local overlay has no values")
    clean: dict[str, str] = {}
    for key, item in values.items():
        key = str(key)
        if not PLACEHOLDER_RE.fullmatch(key):
            raise MergeError(f"invalid overlay placeholder: {key}")
        text = str(item)
        if not text:
            raise MergeError(f"empty overlay value: {key}")
        clean[key] = text
    baseline = value.get("baseline", {})
    if not isinstance(baseline, dict):
        raise MergeError("local overlay baseline must be an object")
    return {"schema": OVERLAY_SCHEMA, "values": clean, "baseline": baseline}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def baseline_changes(target: Path, overlay: dict) -> list[str]:
    changed: list[str] = []
    for rel, expected in sorted(overlay.get("baseline", {}).items()):
        if not is_runtime(rel):
            continue
        path = Path(target) / Path(rel)
        if not path.is_file() or _sha(path.read_bytes()) != str(expected):
            changed.append(rel)
    return changed


def _render_text(data: bytes, values: dict[str, str], rel: str) -> bytes:
    bom = data.startswith(b"\xef\xbb\xbf")
    try:
        text = data.decode("utf-8-sig" if bom else "utf-8")
    except UnicodeDecodeError as exc:
        raise MergeError(f"runtime file is not UTF-8: {rel}") from exc
    for key, value in values.items():
        text = text.replace(key, value)
    remaining = sorted(set(PLACEHOLDER_RE.findall(text)))
    if remaining:
        raise MergeError(f"unresolved placeholders in {rel}: {', '.join(remaining)}")
    encoded = text.encode("utf-8")
    return (b"\xef\xbb\xbf" + encoded) if bom else encoded


def render_staging(staging: Path, manifest: dict, overlay: dict) -> dict:
    """Render runtime files in staging and return a rendered manifest."""
    staging = Path(staging).resolve()
    rendered_files: list[dict] = []
    for entry in manifest.get("files", []):
        rel = _norm(entry["path"])
        path = (staging / Path(rel)).resolve()
        if not path.is_file() or not path.is_relative_to(staging):
            raise MergeError(f"staged file missing or escaped: {rel}")
        data = path.read_bytes()
        if len(data) != int(entry["size"]) or _sha(data) != entry["sha256"]:
            raise MergeError(f"staged file changed before render: {rel}")
        if is_runtime(rel):
            data = _render_text(data, overlay["values"], rel)
            path.write_bytes(data)
        rendered_files.append(
            {"path": rel, "size": len(data), "sha256": _sha(data)}
        )
    rendered_files.sort(key=lambda item: item["path"])
    result = {
        "schema": 1,
        "version": manifest["version"],
        "files": rendered_files,
    }
    return update_core.validate_manifest(result)


def write_manifest(path: Path, manifest: dict) -> None:
    Path(path).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def build_baseline(target: Path) -> dict[str, str]:
    target = Path(target).resolve()
    baseline: dict[str, str] = {}
    for path in target.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(target).as_posix()
        if is_runtime(rel):
            baseline[rel] = _sha(path.read_bytes())
    return dict(sorted(baseline.items()))


def write_overlay(path: Path, values: dict[str, str], target: Path) -> None:
    clean_values = {}
    for key, value in values.items():
        if not PLACEHOLDER_RE.fullmatch(str(key)) or not str(value):
            raise MergeError(f"invalid overlay value: {key}")
        clean_values[str(key)] = str(value)
    overlay = {
        "schema": OVERLAY_SCHEMA,
        "values": dict(sorted(clean_values.items())),
        "baseline": build_baseline(target),
    }
    Path(path).write_text(
        json.dumps(overlay, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def refresh_baseline(target: Path, overlay_path: Path) -> None:
    overlay = load_overlay(overlay_path)
    overlay["baseline"] = build_baseline(target)
    Path(overlay_path).write_text(
        json.dumps(overlay, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def map_overlay_target(path: object) -> str:
    """Map one allow-listed overlay source path to its live target path."""
    value = _norm(path)
    for source_prefix, target_prefix in OVERLAY_TARGETS:
        if value.startswith(source_prefix):
            rest = value[len(source_prefix) :]
            if not rest:
                break
            target = f"{target_prefix}{rest}"
            if not target.startswith(OVERLAY_TARGET_PREFIXES):
                raise MergeError(f"overlay target escaped allow-list: {target}")
            if Path(target).suffix.casefold() not in TEXT_SUFFIXES:
                raise MergeError(f"overlay target is not a code file: {target}")
            return target
    raise MergeError(f"overlay path is not mapped: {value}")


def _safe_under(root: Path, path: Path) -> Path:
    resolved = Path(path).resolve()
    if not resolved.is_relative_to(Path(root).resolve()):
        raise MergeError(f"path escaped root: {path}")
    return resolved


def _hash_file(path: Path) -> str:
    return _sha(Path(path).read_bytes())


def apply_overlay(
    staging: Path,
    target: Path,
    manifest: dict,
    backup: Path | None = None,
) -> dict:
    """Apply manifest overlay files and keep a per-file hash backup."""
    staging = Path(staging).resolve()
    target = Path(target).resolve()
    entries = [
        entry
        for entry in manifest.get("files", [])
        if str(entry.get("path", "")).startswith("overlay/")
    ]
    skipped: list[str] = []
    candidates: list[tuple[dict, str, Path, str]] = []
    for entry in entries:
        source_rel = _norm(entry.get("path"))
        source = _safe_under(staging, staging / Path(source_rel))
        if not source.is_file():
            logger.warning("overlay source missing; skipped: %s", source_rel)
            skipped.append(source_rel)
            continue
        target_rel = map_overlay_target(source_rel)
        if target_rel.startswith("AstrBot/data/plugins/"):
            plugin_name = target_rel[len("AstrBot/data/plugins/") :].split("/", 1)[0]
            plugin_root = target / "AstrBot" / "data" / "plugins" / plugin_name
            if not plugin_root.is_dir():
                logger.warning(
                    "overlay target plugin missing; skipped: %s", target_rel
                )
                skipped.append(source_rel)
                continue
        data = source.read_bytes()
        if len(data) != int(entry.get("size", -1)) or _sha(data) != entry.get(
            "sha256"
        ):
            raise MergeError(f"overlay source hash mismatch: {source_rel}")
        candidates.append((entry, source_rel, source, target_rel))
    if not candidates:
        return {"applied": [], "skipped": skipped, "backup": ""}
    backup = (
        Path(backup)
        if backup
        else target
        / "backups"
        / f"overlay-{time.strftime('%Y%m%d-%H%M%S', time.gmtime())}"
    )
    backup = _safe_under(target / "backups", backup)
    backup.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    try:
        for entry, source_rel, source, target_rel in candidates:
            destination = _safe_under(target, target / Path(target_rel))
            data = source.read_bytes()
            existed = destination.is_file()
            original_hash = _hash_file(destination) if existed else ""
            if existed:
                backup_file = _safe_under(backup, backup / Path(target_rel))
                backup_file.parent.mkdir(parents=True, exist_ok=True)
                backup_file.write_bytes(destination.read_bytes())
                if _hash_file(backup_file) != original_hash:
                    raise MergeError(f"overlay backup hash mismatch: {target_rel}")
            records.append(
                {
                    "source": source_rel,
                    "target": target_rel,
                    "existed": existed,
                    "original_hash": original_hash,
                    "new_hash": _sha(data),
                }
            )
        (backup / "overlay-manifest.json").write_text(
            json.dumps({"schema": 1, "records": records}, ensure_ascii=False, indent=2)
            + "\n",
            encoding="utf-8",
        )
        for record in records:
            source = _safe_under(staging, staging / Path(record["source"]))
            destination = _safe_under(target, target / Path(record["target"]))
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + ".overlay-new")
            temporary.write_bytes(source.read_bytes())
            temporary.replace(destination)
            if _hash_file(destination) != record["new_hash"]:
                raise MergeError(f"overlay apply hash mismatch: {record['target']}")
        return {
            "applied": [record["target"] for record in records],
            "skipped": skipped,
            "backup": str(backup),
        }
    except Exception:
        try:
            restore_overlay(backup, target)
        except Exception as rollback_exc:
            raise MergeError(
                f"overlay apply failed and rollback failed: {rollback_exc}"
            ) from rollback_exc
        raise


def restore_overlay(backup: Path, target: Path) -> dict:
    """Restore an overlay backup and verify every original/new-file hash."""
    backup = Path(backup).resolve()
    target = Path(target).resolve()
    manifest_path = backup / "overlay-manifest.json"
    if not manifest_path.is_file():
        raise MergeError(f"overlay backup manifest missing: {manifest_path}")
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    records = payload.get("records")
    if not isinstance(records, list) or not records:
        raise MergeError("overlay backup has no records")
    restored: list[str] = []
    for record in records:
        target_rel = _norm(record.get("target"))
        destination = _safe_under(target, target / Path(target_rel))
        if record.get("existed"):
            backup_file = _safe_under(backup, backup / Path(target_rel))
            if not backup_file.is_file():
                raise MergeError(f"overlay backup file missing: {target_rel}")
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + ".overlay-restore")
            temporary.write_bytes(backup_file.read_bytes())
            temporary.replace(destination)
            if _hash_file(destination) != str(record.get("original_hash")):
                raise MergeError(f"overlay restore hash mismatch: {target_rel}")
        else:
            destination.unlink(missing_ok=True)
            if destination.exists():
                raise MergeError(f"overlay new file was not removed: {target_rel}")
        restored.append(target_rel)
    return {"restored": restored}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Production overlay renderer")
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check-baseline")
    check.add_argument("--target", required=True)
    check.add_argument("--overlay", required=True)

    render = sub.add_parser("render")
    render.add_argument("--staging", required=True)
    render.add_argument("--manifest", required=True)
    render.add_argument("--overlay", required=True)
    render.add_argument("--out", required=True)

    verify = sub.add_parser("verify-protected")
    verify.add_argument("--manifest", required=True)

    bootstrap = sub.add_parser("bootstrap")
    bootstrap.add_argument("--target", required=True)
    bootstrap.add_argument("--out", required=True)
    bootstrap.add_argument("--values", required=True)

    refresh = sub.add_parser("refresh-baseline")
    refresh.add_argument("--target", required=True)
    refresh.add_argument("--overlay", required=True)

    apply_overlay_parser = sub.add_parser("apply-overlay")
    apply_overlay_parser.add_argument("--staging", required=True)
    apply_overlay_parser.add_argument("--target", required=True)
    apply_overlay_parser.add_argument("--manifest", required=True)
    apply_overlay_parser.add_argument("--backup", default="")

    restore_overlay_parser = sub.add_parser("restore-overlay")
    restore_overlay_parser.add_argument("--backup", required=True)
    restore_overlay_parser.add_argument("--target", required=True)

    args = parser.parse_args(argv)
    try:
        if args.command == "check-baseline":
            changed = baseline_changes(Path(args.target), load_overlay(Path(args.overlay)))
            print(json.dumps({"changed": changed}, ensure_ascii=True))
            return 0 if not changed else 2
        if args.command == "verify-protected":
            manifest = update_core.load_manifest(Path(args.manifest))
            validate_manifest_protected(manifest)
            print(json.dumps({"ok": True}, ensure_ascii=True))
            return 0
        if args.command == "render":
            manifest = update_core.load_manifest(Path(args.manifest))
            validate_manifest_protected(manifest)
            rendered = render_staging(
                Path(args.staging), manifest, load_overlay(Path(args.overlay))
            )
            write_manifest(Path(args.out), rendered)
            print(json.dumps({"rendered": len(rendered["files"])}, ensure_ascii=True))
            return 0
        if args.command == "bootstrap":
            values = json.loads(Path(args.values).read_text(encoding="utf-8-sig"))
            write_overlay(Path(args.out), values, Path(args.target))
            print(json.dumps({"ok": True}, ensure_ascii=True))
            return 0
        if args.command == "refresh-baseline":
            refresh_baseline(Path(args.target), Path(args.overlay))
            print(json.dumps({"ok": True}, ensure_ascii=True))
            return 0
        if args.command == "apply-overlay":
            manifest = update_core.load_manifest(Path(args.manifest))
            result = apply_overlay(
                Path(args.staging),
                Path(args.target),
                manifest,
                Path(args.backup) if args.backup else None,
            )
            print(json.dumps(result, ensure_ascii=True))
            return 0
        if args.command == "restore-overlay":
            result = restore_overlay(Path(args.backup), Path(args.target))
            print(json.dumps(result, ensure_ascii=True))
            return 0
    except (OSError, MergeError, update_core.UpdateSafetyError, ValueError) as exc:
        print(f"MERGE_REJECTED: {exc}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
