"""Production overlay and rendering helpers for update_merge.ps1.

The public release contains placeholders such as YOUR_PROJECT_PATH. This module
keeps deployment values in a local overlay, renders only runtime files, and
builds a second manifest containing the rendered hashes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
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
    except (OSError, MergeError, update_core.UpdateSafetyError, ValueError) as exc:
        print(f"MERGE_REJECTED: {exc}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
