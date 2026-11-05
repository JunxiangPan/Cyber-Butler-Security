"""Pure policy decisions for the broker.

This module has no HTTP or service imports. Callers pass a PolicyContext so the
same functions can be used by the live broker and by isolated policy tests.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


@dataclass(frozen=True)
class PolicyContext:
    root: Path
    shared: Path
    workspace_root: Path
    default_workspace_root: Path
    broker_config: Path
    tmp_roots: tuple[Path, ...]
    memory_roots: tuple[Path, ...]
    totp_vault_root: Path
    critical_names: frozenset[str]
    protected_names: frozenset[str]
    log: Callable[[str], None]


def inside_any(path: Path, roots: tuple[Path, ...]) -> bool:
    try:
        resolved = path.resolve(strict=False)
    except (OSError, ValueError):
        return False
    for root in roots:
        try:
            resolved.relative_to(root.resolve(strict=False))
            return True
        except (OSError, ValueError):
            continue
    return False


def workspace_roots(ctx: PolicyContext) -> tuple[Path, ...]:
    roots = [ctx.workspace_root, ctx.default_workspace_root]
    try:
        data = json.loads(ctx.broker_config.read_text(encoding="utf-8"))
        for key in ("workspace_root", "workspace_path"):
            value = str(data.get(key, "") or "").strip()
            if value:
                roots.append(Path(value))
        shared = data.get("shared_roots", [])
        if isinstance(shared, str):
            shared = [shared]
        if isinstance(shared, (list, tuple)):
            for item in shared:
                text = str(item or "").strip()
                if text:
                    roots.append(Path(text))
    except Exception as exc:
        try:
            ctx.log("broker_config workspace warning: " + str(exc))
        except Exception:
            pass
    return tuple(roots)


def inside_shared(path: Path, ctx: PolicyContext) -> bool:
    if inside_any(path, workspace_roots(ctx)):
        return True
    try:
        path.resolve().relative_to(ctx.shared.resolve())
        return True
    except ValueError:
        return False


def workspace_text(target: str, ctx: PolicyContext) -> bool:
    try:
        def normalise(value: object) -> str:
            return os.path.normcase(os.path.normpath(str(value).replace("\\", "/"))).replace("\\", "/").rstrip("/")
        candidate = normalise(target)
        for root in workspace_roots(ctx):
            normalized = normalise(root)
            if candidate == normalized or candidate.startswith(normalized + "/"):
                return True
    except (OSError, ValueError):
        return False
    return False


def classify(action: str, target: str, ctx: PolicyContext) -> str:
    action = str(action or "").strip().lower()
    if action not in {"delete", "overwrite", "write_file", "send", "send_file"}:
        return "deny"
    if action in {"send", "send_file"}:
        return "totp"
    try:
        path = Path(str(target or "")).resolve(strict=False)
    except (OSError, ValueError):
        return "deny"
    if inside_any(path, (ctx.totp_vault_root,)):
        return "deny"
    if inside_any(path, ctx.tmp_roots):
        return "allow"
    if inside_any(path, workspace_roots(ctx)) or workspace_text(target, ctx):
        return "totp"
    if inside_any(path, ctx.memory_roots):
        return "totp"
    if inside_shared(path, ctx):
        if action == "write_file" and not path.exists():
            return "allow"
        return "totp"
    return "deny"


def critical_integrity_hit(target: str, ctx: PolicyContext) -> bool:
    try:
        path = Path(str(target or "")).resolve(strict=False)
        root = ctx.root.resolve(strict=False)
        path.relative_to(root)
    except (OSError, ValueError):
        return False
    lowered_parts = [part.casefold() for part in path.parts]
    name = path.name.casefold()
    if name in ctx.critical_names:
        return True
    if ".claude" in lowered_parts and name == "settings.json":
        return True
    if ".github" in lowered_parts:
        index = lowered_parts.index(".github")
        if index + 1 < len(lowered_parts) and lowered_parts[index + 1] == "workflows":
            return True
    return False


def rule_tampering_hit(target: str, ctx: PolicyContext) -> bool:
    try:
        path = Path(str(target or "")).resolve(strict=False)
        root = ctx.root.resolve(strict=False)
        path.relative_to(root)
    except (OSError, ValueError):
        return False
    name = path.name.casefold()
    parts = [part.casefold() for part in path.relative_to(ctx.root).parts]
    if name in ctx.protected_names or name.endswith(".chain.jsonl"):
        return True
    if parts and parts[0] in {"tools", "webui", ".github", "installer", "tests"}:
        return True
    return "quarantine" in parts


def allowed_target(path: Path, ctx: PolicyContext) -> bool:
    return inside_shared(path, ctx) or inside_any(path, ctx.tmp_roots) or inside_any(path, ctx.memory_roots)


def target_mode(action: str, target: str) -> str:
    if action == "write_file":
        try:
            return "create" if not Path(target).resolve(strict=False).exists() else "replace"
        except (OSError, ValueError):
            return "replace"
    if action == "overwrite":
        return "replace"
    return action


def bypass_scope(action: str, target: str) -> str:
    path = Path(target).resolve(strict=False)
    return f"{action}:{target_mode(action, target)}:{str(path.parent.resolve(strict=False)).casefold()}"
