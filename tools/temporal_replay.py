"""Read-only Temporal Replay timeline for audit events."""
from __future__ import annotations

import re
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Iterable

_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_REQUIRED = {
    "event_id", "at", "actor", "request_id", "action", "target",
    "before_sha256", "after_sha256", "scope",
}


@dataclass(frozen=True)
class ReplayEvent:
    event_id: str
    at: str
    actor: str
    request_id: str
    action: str
    target: str
    before_sha256: str
    after_sha256: str
    scope: str


def _hash(value: object, *, optional: bool) -> str:
    text = str(value or "").strip().lower()
    if not text and optional:
        return ""
    if not _HEX64.fullmatch(text):
        raise ValueError("hash must be bare 64-character lowercase hex")
    return text


def build_timeline(events: Iterable[dict]) -> list[ReplayEvent]:
    """Validate and sort events; never touches the filesystem."""
    timeline: list[ReplayEvent] = []
    seen: set[str] = set()
    for raw in events:
        if not isinstance(raw, dict):
            raise ValueError("event must be an object")
        if set(raw) != _REQUIRED:
            raise ValueError("event fields do not match the replay schema")
        event_id = str(raw["event_id"]).strip()
        if not event_id or event_id in seen:
            raise ValueError("event_id must be non-empty and unique")
        seen.add(event_id)
        try:
            datetime.fromisoformat(str(raw["at"]).replace("Z", "+00:00"))
        except ValueError as exc:
            raise ValueError("at must be ISO-8601") from exc
        before = _hash(raw["before_sha256"], optional=True)
        after = _hash(raw["after_sha256"], optional=True)
        if before == after:
            raise ValueError("before/after hashes must differ")
        if not before and str(raw["action"]).lower() not in {"create", "write"}:
            raise ValueError("missing before hash for a mutating action")
        if not after and str(raw["action"]).lower() not in {"delete"}:
            raise ValueError("missing after hash for a non-delete action")
        timeline.append(ReplayEvent(
            event_id=event_id,
            at=str(raw["at"]),
            actor=str(raw["actor"]),
            request_id=str(raw["request_id"]),
            action=str(raw["action"]),
            target=str(raw["target"]),
            before_sha256=before,
            after_sha256=after,
            scope=str(raw["scope"]),
        ))
    return sorted(timeline, key=lambda item: (item.at, item.event_id))


def replay_summary(events: Iterable[dict]) -> dict:
    """Return a compact evidence summary without replaying any action."""
    timeline = build_timeline(events)
    return {
        "events": len(timeline),
        "actions": sorted({item.action for item in timeline}),
        "targets": sorted({item.target for item in timeline}),
        "actors": sorted({item.actor for item in timeline}),
        "timeline": [asdict(item) for item in timeline],
    }
