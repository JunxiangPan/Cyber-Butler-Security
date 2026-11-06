#!/usr/bin/env python3
"""Three local gates run before packaging.

1. Text hygiene + placeholder allowlist
2. Installer dry-run (paths / Unicode / token ACL readback)
3. Required wheelhouse and critical-file presence
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {".ps1", ".py", ".json", ".md"}
BINARY_SUFFIXES = {
    ".exe", ".dll", ".whl", ".png", ".jpg", ".jpeg", ".gif", ".ico",
    ".pyc", ".pyd", ".pdb", ".zip", ".gz", ".ttf", ".woff", ".woff2",
    ".db", ".graph", ".pdf",
}
SKIP_PARTS = {".git", ".venv", "__pycache__", "wheelhouse", "node_modules",
              "tmp-webui-tests", "tmp-webui-block1-final", "YOUR_PROJECT_PATH"}


def allowlist() -> set[str]:
    path = ROOT / "quality" / "placeholder_allowlist.txt"
    if not path.is_file():
        raise SystemExit("missing quality/placeholder_allowlist.txt")
    return {
        line.strip().replace("\\", "/")
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    }


def hygiene() -> list[str]:
    allowed = allowlist()
    problems: list[str] = []
    listed = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, capture_output=True
    )
    if listed.returncode != 0:
        raise SystemExit("git ls-files failed; cannot establish package scope")
    for raw in listed.stdout.split(bytes([0])):
        if not raw:
            continue
        rel = raw.decode("utf-8", "replace").replace("\\", "/")
        if (
            rel.startswith(("overlay/", "plugins/", "quality/", ".cbp/"))
            or rel in {"FINAL_QA_REPORT.md", "quality-manifest.json", "quality-manifest.sha256"}
        ):
            continue
        path = ROOT / rel
        if not path.is_file() or path.suffix.lower() in BINARY_SUFFIXES:
            continue
        data = path.read_bytes()
        if b"\x00" in data:
            problems.append(f"{rel}: NUL byte")
            continue
        for index, value in enumerate(data):
            if value < 32 and value not in (9, 10, 13):
                problems.append(f"{rel}: control 0x{value:02x} at {index}")
                break
        if data.startswith(b"\xef\xbb\xbf\xef\xbb\xbf"):
            problems.append(f"{rel}: double UTF-8 BOM")
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            problems.append(f"{rel}: invalid UTF-8: {exc}")
            continue
        if "YOUR_" in text and rel not in allowed and not rel.startswith(("docs/", "checks/snapshot/", "cbp-action/")) and rel != "README.md":
            problems.append(f"{rel}: unexpected YOUR_ placeholder")
    return problems


def dry_run() -> list[str]:
    script = ROOT / "quality" / "installer_dry_run.ps1"
    if not script.is_file():
        return ["missing quality/installer_dry_run.ps1"]
    result = subprocess.run(
        ["pwsh.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
         "-File", str(script)],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        return [f"installer dry-run failed: {result.stdout} {result.stderr}"]
    if "DRY_RUN_OK" not in result.stdout:
        return [f"installer dry-run did not report OK: {result.stdout}"]
    return []


def required_files() -> list[str]:
    problems: list[str] = []
    required = [
        "VERSION", "START-INSTALLER.exe",
        "installer/Install-CyberButler.ps1",
        "installer/core-sources.json",
        "webui/requirements.txt",
        "dependencies.sbom.json",
    ]
    for rel in required:
        if not (ROOT / rel).is_file():
            problems.append(f"missing required file: {rel}")
    wheelhouse = ROOT / "installer" / "wheelhouse"
    wheels = sorted(wheelhouse.glob("*.whl")) if wheelhouse.is_dir() else []
    if len(wheels) < 27:
        problems.append(f"wheelhouse incomplete: {len(wheels)} wheels")
    required_wheels = ("fastapi-", "uvicorn-", "pyotp-", "qrcode-", "pywin32-", "pillow-")
    names = "\n".join(path.name.lower() for path in wheels)
    for prefix in required_wheels:
        if prefix not in names:
            problems.append(f"wheelhouse missing {prefix}")
    return problems


def main() -> int:
    problems = hygiene() + dry_run() + required_files()
    if problems:
        print("PACKAGING_GATE_FAILED", file=sys.stderr)
        for item in problems:
            print("  " + item, file=sys.stderr)
        return 1
    print("PACKAGING_GATES_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
