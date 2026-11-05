"""Broker health watchdog and fail-closed marker for the agent side."""

from __future__ import annotations

import json
import os
import time
import urllib.request
from pathlib import Path


def check_health(url: str = "http://127.0.0.1:18090/health", timeout: float = 1.5) -> bool:
    """Check health.
    
    Args:
        url: caller-supplied value.
        timeout: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            if response.status != 200:
                return False
            payload = json.loads(response.read().decode("utf-8"))
            return payload.get("ok") is True and payload.get("service") == "totp-broker"
    except Exception:
        return False


def state_path(root: str | Path) -> Path:
    """State path.
    
    Args:
        root: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return Path(root) / "tools" / "broker-health.json"


def write_state(root: str | Path, healthy: bool) -> dict:
    """Write state.
    
    Args:
        root: caller-supplied value.
        healthy: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    path = state_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "healthy": bool(healthy),
        "checked_at": int(time.time()),
    }
    path.write_text(json.dumps(record, sort_keys=True), encoding="utf-8")
    return record


def is_fail_closed(root: str | Path) -> bool:
    """Agent must deny high-risk tools when the last probe was unhealthy."""
    path = state_path(root)
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("healthy") is not True
    except (OSError, ValueError):
        return True


def run_once(root: str | Path, url: str = "http://127.0.0.1:18090/health") -> dict:
    """Run once.
    
    Args:
        root: caller-supplied value.
        url: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    healthy = check_health(url)
    return write_state(root, healthy)


def main() -> int:
    """Main.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    root = os.environ.get("CBS_ROOT", r"C:\CyberButler")
    interval = max(1, int(os.environ.get("CBS_WATCHDOG_INTERVAL", "2")))
    while True:
        run_once(root)
        time.sleep(interval)


if __name__ == "__main__":
    raise SystemExit(main())
