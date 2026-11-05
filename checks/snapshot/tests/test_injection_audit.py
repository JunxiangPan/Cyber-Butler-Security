from __future__ import annotations

from pathlib import Path

import injection_audit


def test_external_read_creates_warning(tmp_path, monkeypatch):
    monkeypatch.setattr(injection_audit, "EVENT_FILE", tmp_path / "external-reads.jsonl")
    assert injection_audit.warning() == ""
    event = injection_audit.record("web", "https://example.com/article")
    assert event["kind"] == "web"
    assert injection_audit.warning() == injection_audit.WARNING
    assert "example.com" in injection_audit.recent()[0]["source"]


def test_invalid_kind_is_rejected(tmp_path, monkeypatch):
    monkeypatch.setattr(injection_audit, "EVENT_FILE", tmp_path / "external-reads.jsonl")
    try:
        injection_audit.record("email", "x")
    except ValueError:
        return
    raise AssertionError("invalid kind accepted")


def test_old_event_does_not_warn(tmp_path, monkeypatch):
    monkeypatch.setattr(injection_audit, "EVENT_FILE", tmp_path / "external-reads.jsonl")
    path = tmp_path / "external-reads.jsonl"
    path.write_text('{"at":"2000-01-01T00:00:00+00:00","kind":"web","source":"old"}\n', encoding="utf-8")
    assert injection_audit.warning() == ""
