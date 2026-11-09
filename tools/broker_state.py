#!/usr/bin/env python3
"""Pure Broker state/policy helpers extracted from broker.py."""
from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import urlparse


def _url_host_allowed(url: str) -> bool:
    """SSRF gate: URL entries must target an explicitly allowed host."""
    try:
        from urllib.parse import urlparse
        host = (urlparse(url).hostname or "").casefold()
    except ValueError:
        return False
    if not host:
        return False
    allowed = os.environ.get("CBS_URL_ALLOWED_HOSTS", "")
    hosts = {item.strip().casefold() for item in allowed.split(",") if item.strip()}
    return host in hosts


def _target_mode(action: str, target: str) -> str:
    """Target mode.
    
    Args:
        action: caller-supplied value.
        target: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if action == "write_file":
        try:
            return "create" if not Path(target).resolve(strict=False).exists() else "replace"
        except (OSError, ValueError):
            return "replace"
    if action == "overwrite":
        return "replace"
    return action


def _bypass_scope(action: str, target: str) -> str:
    """Bypass scope.
    
    Args:
        action: caller-supplied value.
        target: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    path = Path(target).resolve(strict=False)
    return f"{action}:{_target_mode(action, target)}:{str(path.parent.resolve(strict=False)).casefold()}"


def _as_bool(value: object) -> bool:
    """As bool.
    
    Args:
        value: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}

