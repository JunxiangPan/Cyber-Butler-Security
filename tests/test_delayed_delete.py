"""Two-Stage Delayed Delete: staging, ACL-disabled unit paths, undo, purge."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import pytest

import broker
import quarantine
from win_path_guard import TargetSnapshot


@pytest.fixture(autouse=True)
def no_windows_acl(monkeypatch):
    monkeypatch.setenv("CBS_DISABLE_ACL", "1")


def _stage(tmp_path: Path, monkeypatch, request_id: str = "req-1") -> tuple[Path, Path]:
    root = tmp_path / "staging"
    monkeypatch.setattr(quarantine, "TRASH_STAGING", root)
    monkeypatch.setattr(quarantine, "MAX_BYTES", 2 * 1024 * 1024)
    target = tmp_path / "important.txt"
    target.write_text("important", encoding="utf-8")
    snapshot = TargetSnapshot.open(str(target), write=True)
    entry = quarantine.quarantine_file(
        snapshot, request_id, original_path=str(target), action="delete", reason="test"
    )
    assert not target.exists()
    return entry, target


def test_quarantine_moves_and_undo_restores(tmp_path, monkeypatch):
    entry, original = _stage(tmp_path, monkeypatch)
    pending = quarantine.list_pending()
    assert pending and pending[0]["id"] == "req-1"
    quarantine.restore_quarantine(entry, original)
    assert original.read_text(encoding="utf-8") == "important"
    manifest = json.loads((entry / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["state"] == "restored"


def test_expired_entry_is_securely_removed(tmp_path, monkeypatch):
    entry, _ = _stage(tmp_path, monkeypatch)
    manifest_path = entry / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["expires_epoch"] = 0
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    payload = Path(manifest["quarantine_path"])
    assert payload.exists()
    assert quarantine.purge_expired() >= 1
    assert not entry.exists()


def test_capacity_breaker_keeps_original(tmp_path, monkeypatch):
    root = tmp_path / "staging"
    monkeypatch.setattr(quarantine, "TRASH_STAGING", root)
    monkeypatch.setattr(quarantine, "MAX_BYTES", 1)
    target = tmp_path / "large.txt"
    target.write_text("too large", encoding="utf-8")
    snapshot = TargetSnapshot.open(str(target), write=True)
    with pytest.raises(quarantine.QuarantineCapacityError):
        quarantine.quarantine_file(
            snapshot, "req-cap", original_path=str(target), action="delete"
        )
    assert target.exists()
    snapshot.close()


def test_broker_undo_api(tmp_path, monkeypatch):
    entry, original = _stage(tmp_path, monkeypatch)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp_path,))
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    status, body = broker.undo_trash_request({"id": "req-1"})
    assert status == 200
    assert original.read_text(encoding="utf-8") == "important"
    assert body["restored"] == str(original)
