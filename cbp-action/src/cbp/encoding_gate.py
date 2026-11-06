"""Strict UTF-8 no-BOM gate for tracked text files."""
from __future__ import annotations

import codecs
import subprocess
from pathlib import Path

from .config import GateConfig

TEXT_SUFFIXES = {
    ".md", ".yml", ".yaml", ".py", ".json", ".toml", ".txt", ".csv",
    ".ps1", ".cs", ".csproj", ".xml", ".sh", ".cfg", ".ini", ".html",
    ".css", ".js", ".ts", ".tsx", ".jsx",
}
SKIP_PARTS = {".git", ".venv", "site-packages", "node_modules", "__pycache__", "dist", "build"}


def _tracked(root: Path) -> list[Path]:
    try:
        completed = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            capture_output=True,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        completed = None
    if completed and completed.returncode == 0 and completed.stdout:
        names = [item for item in completed.stdout.decode("utf-8", "replace").split("\x00") if item]
        return [root / name for name in names if not (set(Path(name).parts) & SKIP_PARTS)]
    return [
        path for path in root.rglob("*")
        if path.is_file() and not (set(path.parts) & SKIP_PARTS)
    ]


def _text_files(root: Path) -> list[Path]:
    return sorted(
        path for path in _tracked(root)
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES
    )


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Reject BOM-prefixed or non-UTF-8 tracked text files."""
    bad: list[str] = []
    files = _text_files(cfg.root)
    for path in files:
        try:
            data = path.read_bytes()
        except OSError as exc:
            bad.append(f"{path.relative_to(cfg.root)}: read error: {exc}")
            continue
        if data.startswith(codecs.BOM_UTF8):
            bad.append(f"{path.relative_to(cfg.root)}: UTF-8 BOM")
            continue
        if data.startswith(codecs.BOM_UTF16_LE) or data.startswith(codecs.BOM_UTF16_BE):
            bad.append(f"{path.relative_to(cfg.root)}: UTF-16 BOM")
            continue
        try:
            data.decode("utf-8", "strict")
        except UnicodeDecodeError as exc:
            bad.append(f"{path.relative_to(cfg.root)}: invalid UTF-8: {exc}")
    if bad:
        return False, "\n".join(bad[:80]) + f"\nfindings={len(bad)}"
    return True, f"encoding={len(files)} UTF-8 files without BOM"
