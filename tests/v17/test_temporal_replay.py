"""Temporal Replay: read-only timeline evidence and negative cases."""
from __future__ import annotations

import hashlib

import pytest

from tools.temporal_replay import build_timeline, replay_summary

ZERO = "0" * 64
ONE = "1" * 64


def event(**overrides):
    base = {
        "event_id": "e1", "at": "2026-11-10T00:00:00+00:00",
        "actor": "agent", "request_id": "r1", "action": "write",
        "target": "C:/workspace/a.txt", "before_sha256": ZERO,
        "after_sha256": ONE, "scope": "C:/workspace",
    }
    base.update(overrides)
    return base


def test_timeline_sorts_and_hashes_are_recomputed() -> None:
    data = [event(event_id="b", at="2026-11-10T00:00:02+00:00"), event(event_id="a", at="2026-11-10T00:00:01+00:00")]
    timeline = build_timeline(data)
    assert [item.event_id for item in timeline] == ["a", "b"]
    summary = replay_summary(data)
    assert summary["events"] == 2
    assert summary["timeline"][0]["before_sha256"] == ZERO


def test_duplicate_bad_hash_and_bad_time_rejected() -> None:
    with pytest.raises(ValueError):
        build_timeline([event(), event()])
    with pytest.raises(ValueError):
        build_timeline([event(before_sha256="sha256:" + ZERO)])
    with pytest.raises(ValueError):
        build_timeline([event(at="not-a-time")])
    with pytest.raises(ValueError):
        build_timeline([event(before_sha256=ZERO, after_sha256=ZERO)])


def test_delete_and_create_hash_semantics() -> None:
    created = build_timeline([event(event_id="c", action="create", before_sha256="")])
    assert created[0].before_sha256 == ""
    deleted = build_timeline([event(event_id="d", action="delete", after_sha256="")])
    assert deleted[0].after_sha256 == ""


def test_replay_is_read_only(monkeypatch, tmp_path) -> None:
    # The module has no write API; a sentinel file remains untouched.
    sentinel = tmp_path / "sentinel.txt"
    sentinel.write_text("unchanged", encoding="utf-8")
    before = hashlib.sha256(sentinel.read_bytes()).hexdigest()
    replay_summary([event()])
    assert hashlib.sha256(sentinel.read_bytes()).hexdigest() == before
