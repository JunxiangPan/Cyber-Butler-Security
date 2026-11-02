"""Record the owner's explicit physical-separation acknowledgement."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


def state_path(root: str | Path) -> Path:
    return Path(root) / "tools" / "physical-separation.json"


def acknowledge(root: str | Path, separate_device: bool) -> dict:
    path = state_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "schema": 1,
        "separate_device": bool(separate_device),
        "acknowledged_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    path.write_text(json.dumps(record, sort_keys=True, indent=2), encoding="utf-8")
    return record


def is_separated(root: str | Path) -> bool:
    try:
        record = json.loads(state_path(root).read_text(encoding="utf-8"))
        return record.get("separate_device") is True
    except (OSError, ValueError):
        return False
