"""Undo trash branch coverage."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


def test_undo_validation_and_missing(monkeypatch, tmp_path) -> None:
    assert broker.undo_trash_request({"id": ""})[0] == 400
    assert broker.undo_trash_request({"id": "bad/../id"})[0] == 400
    monkeypatch.setattr(broker.quarantine, "TRASH_STAGING", tmp_path)
    assert broker.undo_trash_request({"id": "missing"})[0] == 404


def test_undo_success_and_errors(monkeypatch, tmp_path) -> None:
    staging = tmp_path / "staging"; staging.mkdir()
    entry = staging / "ok"; entry.mkdir()
    target = tmp_path / "restored.txt"
    monkeypatch.setattr(broker.quarantine, "TRASH_STAGING", staging)
    monkeypatch.setattr(broker.quarantine, "_read_manifest", lambda entry: {"original_path": str(target)})
    monkeypatch.setattr(broker, "_allowed_target", lambda path: True)
    monkeypatch.setattr(broker.quarantine, "restore_quarantine", lambda e, d: d)
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    status, body = broker.undo_trash_request({"id": "ok"})
    assert status == 200 and body["restored"] == str(target)
    monkeypatch.setattr(broker.quarantine, "restore_quarantine", lambda e, d: (_ for _ in ()).throw(FileExistsError()))
    assert broker.undo_trash_request({"id": "ok"})[0] == 409
    monkeypatch.setattr(broker.quarantine, "restore_quarantine", lambda e, d: (_ for _ in ()).throw(OSError("broken")))
    assert broker.undo_trash_request({"id": "ok"})[0] == 409
