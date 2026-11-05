"""Deterministic approval previews for the Broker.

The owner must never approve an AI-written summary. This module builds the
preview from the real target bytes/stat data, adds a bounded unified diff, and
redacts credential-looking strings before the text reaches QQ or email.
"""

from __future__ import annotations

import difflib
import hashlib
import os
import re
from pathlib import Path
from typing import Any

SCRIPT_SUFFIXES = {".py", ".ps1", ".bat", ".cmd", ".vbs", ".js", ".ts", ".sh"}
_SECRET_RE = re.compile(
    r"(?i)(api[_-]?key|token|secret|password|passwd|authorization)"
    r"(\s*[:=]\s*)([^\s,;]+)"
)
MAX_PREVIEW_BYTES = 256 * 1024
MAX_DIFF_LINES = 80
MAX_DIFF_CHARS = 8 * 1024
INTENT_READ_RE = re.compile(r"(?i)(读取|查看|查询|检查|查|读|读一下|看一下|read|check|inspect|view|改\s*ui|修改\s*ui|改界面|修改界面|ui|test|css|format)")
SENSITIVE_TARGET_RE = re.compile(r"(?i)(config|env|auth|secret|id_rsa|system32|pytest\.ini|conftest\.py)")
SENSITIVE_NAMES = {".env", "pytest.ini", "conftest.py", "auth", "config"}
MAGIC_TYPES = ((b"#!", "Shebang"), (b"MZ", "PE"), (b"ELF", "ELF"))


def _magic_type(data: bytes) -> str | None:
    """Magic type.
    
    Args:
        data: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    for prefix, label in MAGIC_TYPES:
        if data.startswith(prefix):
            return label
    return None


def _magic_head(path: Path) -> bytes:
    """Magic head.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        with path.open("rb") as handle:
            return handle.read(8)
    except OSError:
        return b""


def _intent_mismatch(reason: str, target: Path) -> bool:
    """Intent mismatch.
    
    Args:
        reason: caller-supplied value.
        target: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if not INTENT_READ_RE.search(reason or ""):
        return False
    name = target.name.casefold()
    parts = [part.casefold() for part in target.parts]
    return (
        bool(SENSITIVE_TARGET_RE.search(str(target)))
        or name in SENSITIVE_NAMES
        or name.startswith(".env")
        or name.startswith("config.")
        or name.startswith("auth.")
        or "config" in parts
        or "auth" in parts
    )


def _redact(text: str) -> str:
    """Redact.
    
    Args:
        text: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return _SECRET_RE.sub(lambda m: m.group(1) + m.group(2) + "[REDACTED]", text)


def _stat(path: Path) -> dict[str, Any]:
    """Stat.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        stat = path.stat()
    except OSError:
        return {"exists": False}
    return {
        "exists": True,
        "size": int(stat.st_size),
        "mtime": int(stat.st_mtime_ns),
        "sha256": _hash_file(path),
    }


def _hash_file(path: Path) -> str:
    """Hash file.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError:
        return ""
    return digest.hexdigest()


def _text(path: Path) -> str | None:
    """Text.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if len(data) > MAX_PREVIEW_BYTES or b"\x00" in data:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _diff(old: str | None, new: str | None) -> tuple[str, bool]:
    """Diff.
    
    Args:
        old: caller-supplied value.
        new: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if old is None or new is None:
        return "", False
    lines = list(
        difflib.unified_diff(
            old.splitlines(),
            new.splitlines(),
            fromfile="before",
            tofile="after",
            lineterm="",
            n=3,
        )
    )
    truncated = len(lines) > MAX_DIFF_LINES
    text = "\n".join(lines[:MAX_DIFF_LINES])
    if len(text) > MAX_DIFF_CHARS:
        text = text[:MAX_DIFF_CHARS]
        truncated = True
    return _redact(text), truncated


def build_preview(
    action: str,
    target: str,
    *,
    content: str | None = None,
    source: str = "",
    reason: str = "",
) -> dict[str, Any]:
    """Build a bounded, deterministic preview from real file bytes."""
    target_path = Path(str(target))
    target_info = _stat(target_path)
    preview: dict[str, Any] = {
        "action": action,
        "target": str(target_path),
        "kind": "delete" if action == "delete" else ("create" if not target_info["exists"] else "replace"),
        "before": target_info,
        "script_warning": target_path.suffix.lower() in SCRIPT_SUFFIXES,
        "magic_warning": False,
        "magic_types": [],
        "intent_mismatch": _intent_mismatch(reason, target_path),
        "intent_reason": str(reason or "")[:300],
    }
    if action == "delete":
        return preview
    if target_info.get("exists"):
        target_magic = _magic_type(_magic_head(target_path))
        if target_magic:
            preview["magic_types"].append(target_magic)
    preview["magic_warning"] = bool(preview["magic_types"])
    if action == "overwrite":
        source_path = Path(str(source))
        source_info = _stat(source_path)
        preview["source"] = source_info
        source_magic = _magic_type(_magic_head(source_path))
        if source_magic and source_magic not in preview["magic_types"]:
            preview["magic_types"].append(source_magic)
        preview["magic_warning"] = bool(preview["magic_types"])
        if target_info.get("exists") and source_info.get("exists"):
            preview["diff"], preview["diff_truncated"] = _diff(
                _text(target_path), _text(source_path)
            )
            preview["binary"] = _text(target_path) is None or _text(source_path) is None
        return preview

    new_text = content if isinstance(content, str) else None
    if new_text is not None:
        content_magic = _magic_type(new_text.encode("utf-8")[:8])
        if content_magic and content_magic not in preview["magic_types"]:
            preview["magic_types"].append(content_magic)
    preview["magic_warning"] = bool(preview["magic_types"])
    preview["after_size"] = len((new_text or "").encode("utf-8"))
    if new_text is not None:
        preview["after_sha256"] = hashlib.sha256(new_text.encode("utf-8")).hexdigest()
    if target_info.get("exists") and new_text is not None:
        old_text = _text(target_path)
        if old_text is not None:
            preview["diff"], preview["diff_truncated"] = _diff(old_text, new_text)
            preview["binary"] = False
        else:
            preview["diff"] = ""
            preview["diff_truncated"] = True
            preview["binary"] = True
    return preview


def format_preview(preview: dict[str, Any], request_id: str = "") -> str:
    """Render the owner-facing prompt; never includes the AI reason field."""
    lines = ["哥，以下是底层真实参数，未经 Agent 转述。"]
    if preview.get("script_warning"):
        lines.append("扩展名属于脚本类型")
    if preview.get("magic_warning"):
        types = ", ".join(preview.get("magic_types") or [])
        lines.append(f"目标内容包含可执行代码特征（{types}）")
    if preview.get("intent_mismatch"):
        lines.insert(0, "⚠️ INTENT MISMATCH: Agent claims [" + str(preview.get("intent_reason", ""))[:300] + "], but targets [" + str(preview.get("target", ""))[:300] + "]")
    if preview.get("external_read_warning"):
        lines.append(str(preview["external_read_warning"]))
    lines.append(f"动作：{preview.get('action')}")
    lines.append(f"目标：{preview.get('target')}")
    if preview.get("kind") == "delete":
        before = preview.get("before") or {}
        lines.append(f"文件大小：{before.get('size')} bytes")
        lines.append(f"修改时间：{before.get('mtime')}")
        lines.append(f"sha256：{before.get('sha256')}")
    else:
        before = preview.get("before") or {}
        lines.append(f"原大小：{before.get('size', 0)} bytes")
        lines.append(f"新大小：{preview.get('after_size', 0)} bytes")
        if preview.get("source"):
            src = preview["source"]
            lines.append(f"来源：{src.get('size')} bytes | sha256={src.get('sha256')}")
        if preview.get("diff"):
            lines.append("Diff：")
            lines.append(preview["diff"])
            lines.append("[Diff 已截断]" if preview.get("diff_truncated") else "[Diff 结束]")
        elif preview.get("binary"):
            lines.append("[二进制或超大文件，Diff 已省略]")
    lines.append("仅本次：<6 位动态码>")
    lines.append("同一目录同动作 30 秒：<6 位动态码> BYPASS 30")
    lines.append("当前草稿目录 30 分钟：<6 位动态码> SCOPED 30")
    if request_id:
        lines.append(f"请求号：{request_id}")
    return "\n".join(lines)
