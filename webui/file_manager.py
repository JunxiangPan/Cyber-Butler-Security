from __future__ import annotations

import fnmatch
import json
import mimetypes
import os
import re
from pathlib import Path

from settings import Settings


class FileAccessError(RuntimeError):
    pass


BLOCKED_EXTENSIONS = {
    ".exe", ".bat", ".cmd", ".com", ".scr", ".msi", ".msp", ".dll", ".sys",
    ".ps1", ".psm1", ".py", ".pyw", ".js", ".mjs", ".vbs", ".vbe", ".jar",
    ".sh", ".bash", ".zsh", ".lnk", ".reg", ".hta", ".html", ".htm", ".svg",
    ".apk", ".dmg", ".iso", ".img", ".msix",
}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp"}
TEXT_EXTENSIONS = {".txt", ".md", ".log", ".csv", ".json", ".yaml", ".yml", ".ini", ".conf", ".rst"}
PDF_EXTENSIONS = {".pdf"}
MAX_ENTRIES = 200
DRIVE_RE = re.compile(r"^[A-Za-z]:")


def _is_link(path: Path) -> bool:
    return path.is_symlink() or bool(getattr(os.path, "isjunction", lambda _: False)(path))


class FileManager:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.max_bytes = max(1, int(settings.file_max_mb)) * 1024 * 1024
        self.deny_patterns = tuple(str(item).lower() for item in settings.file_deny_patterns)

    def _root(self) -> Path:
        raw = str(self.settings.file_root or "").strip()
        if self.settings.config_path:
            try:
                data = json.loads(Path(self.settings.config_path).read_text(encoding="utf-8"))
                candidate = str(data.get("file_root") or "").strip()
                if candidate:
                    raw = candidate
            except (OSError, ValueError):
                pass
        if not raw:
            raise FileAccessError("file manager is not configured")
        try:
            root = Path(raw).resolve(strict=True)
        except OSError as exc:
            raise FileAccessError("configured file root is unavailable") from exc
        if not root.is_dir():
            raise FileAccessError("configured file root is not a directory")
        return root

    def _resolve(self, relative: str) -> tuple[Path, Path]:
        root = self._root()
        raw = str(relative or "").strip()
        if "\x00" in raw:
            raise FileAccessError("invalid path")
        if raw.startswith(("/", "\\")) or raw.startswith("//") or DRIVE_RE.match(raw):
            raise FileAccessError("absolute paths are not allowed")
        if ".." in raw:
            raise FileAccessError("parent traversal is not allowed")
        parts = [part for part in raw.replace("\\", "/").split("/") if part not in ("", ".")]
        current = root
        for part in parts:
            current = current / part
            if _is_link(current):
                raise FileAccessError("symlinks are not allowed")
        try:
            target = (root.joinpath(*parts)).resolve(strict=True)
        except OSError as exc:
            raise FileAccessError("path not found") from exc
        root_norm = os.path.normcase(str(root))
        target_norm = os.path.normcase(str(target))
        if target_norm != root_norm and not target_norm.startswith(root_norm + os.sep):
            raise FileAccessError("path escapes the configured root")
        return root, target

    def _denied_name(self, name: str) -> bool:
        lower = name.lower()
        if lower.startswith("."):
            return True
        if any(fnmatch.fnmatch(lower, pattern) for pattern in self.deny_patterns):
            return True
        return Path(name).suffix.lower() in BLOCKED_EXTENSIONS

    def list_dir(self, relative: str = "") -> dict:
        _, target = self._resolve(relative)
        if not target.is_dir():
            raise FileAccessError("not a directory")
        rel_base = relative.replace("\\", "/").strip("/")
        entries = []
        for child in target.iterdir():
            if len(entries) >= MAX_ENTRIES:
                break
            if _is_link(child) or self._denied_name(child.name):
                continue
            try:
                if child.is_dir():
                    entries.append({
                        "name": child.name,
                        "path": (f"{rel_base}/{child.name}" if rel_base else child.name).strip("/"),
                        "is_dir": True,
                        "size": None,
                        "mtime": int(child.stat().st_mtime),
                    })
                elif child.is_file():
                    stat = child.stat()
                    entries.append({
                        "name": child.name,
                        "path": (f"{rel_base}/{child.name}" if rel_base else child.name).strip("/"),
                        "is_dir": False,
                        "size": int(stat.st_size),
                        "mtime": int(stat.st_mtime),
                    })
            except OSError:
                continue
        entries.sort(key=lambda item: (not item["is_dir"], item["name"].lower()))
        return {
            "ok": True,
            "path": rel_base,
            "entries": entries,
            "truncated": len(entries) >= MAX_ENTRIES,
            "max_mb": self.settings.file_max_mb,
        }

    def file_info(self, relative: str) -> dict:
        _, target = self._resolve(relative)
        if not target.is_file():
            raise FileAccessError("not a file")
        if self._denied_name(target.name):
            raise FileAccessError("file type is blocked")
        stat = target.stat()
        if stat.st_size > self.max_bytes:
            raise FileAccessError("file exceeds the download limit")
        suffix = target.suffix.lower()
        if suffix in IMAGE_EXTENSIONS:
            category = "image"
            media_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        elif suffix in TEXT_EXTENSIONS:
            category = "text"
            media_type = "text/plain; charset=utf-8"
        elif suffix in PDF_EXTENSIONS:
            category = "pdf"
            media_type = "application/pdf"
        else:
            category = "download"
            media_type = "application/octet-stream"
        return {
            "ok": True,
            "path": relative.replace("\\", "/").strip("/"),
            "name": target.name,
            "size": int(stat.st_size),
            "mtime": int(stat.st_mtime),
            "category": category,
            "media_type": media_type,
            "target": target,
        }
