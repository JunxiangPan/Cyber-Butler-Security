"""P0 Broker tests: send manifest binding, URL/outside approval, tamper rejection."""

from __future__ import annotations

import hashlib
import time
from pathlib import Path

import broker


def setup_function() -> None:
    broker._pending = None
    broker._verify_locked_until = 0.0
    broker._global_failures = 0
    broker._global_lock_until = 0.0
    broker._last_request_at = 0.0


def _entry(path: Path) -> dict:
    data = path.read_bytes()
    return {
        "kind": "file",
        "path": str(path.resolve()),
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def test_send_without_manifest_is_rejected(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(broker, "SHARED", tmp_path)
    status, body = broker.run_request(
        {"action": "send", "target": str(tmp_path / "note.txt")}
    )
    assert status == 409
    assert "manifest" in body["error"]


def test_send_outside_shared_folder_is_challenged(monkeypatch, tmp_path) -> None:
    shared = tmp_path / "shared"
    shared.mkdir()
    outside = tmp_path / "outside.txt"
    outside.write_text("outside", encoding="utf-8")
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "TIMEOUT_SECONDS", 0.01)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)

    status, body = broker.run_request(
        {
            "action": "send",
            "target": str(outside),
            "manifest": [_entry(outside)],
        }
    )

    # The owner must receive a challenge; the old 403 dead end is gone.
    assert status == 408
    assert body.get("approved") is False
    assert broker._pending is None


def test_send_url_is_challenged(monkeypatch, tmp_path) -> None:
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "TIMEOUT_SECONDS", 0.01)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)

    status, body = broker.run_request(
        {
            "action": "send",
            "target": "https://example.com/image.png",
            "manifest": [
                {
                    "kind": "url",
                    "path": "https://example.com/image.png",
                    "size": 0,
                    "sha256": "",
                }
            ],
        }
    )

    assert status == 408
    assert body.get("approved") is False
    assert broker._pending is None


def test_manifest_tamper_is_rejected_at_approval(monkeypatch, tmp_path) -> None:
    shared = tmp_path / "shared"
    shared.mkdir()
    target = shared / "note.txt"
    target.write_text("original", encoding="utf-8")
    manifest = [_entry(target)]
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "verify_code", lambda code: "totp")

    broker._pending = {
        "id": "manifest-tamper",
        "action": "send",
        "target": str(target),
        "source": "",
        "reason": "test",
        "deadline": time.monotonic() + 60,
        "manifest": manifest,
    }
    target.write_text("tampered", encoding="utf-8")

    status, body = broker.run_verify({"id": "manifest-tamper", "code": "123456"})

    assert status == 409
    assert broker._pending is None
    assert "manifest" in body["error"]
    assert audit.exists()


def test_manifest_prompt_uses_full_path_and_outside_marker(monkeypatch, tmp_path) -> None:
    shared = tmp_path / "shared"
    shared.mkdir()
    inside = shared / "inside.txt"
    inside.write_text("inside", encoding="utf-8")
    outside = tmp_path / "outside.txt"
    outside.write_text("outside", encoding="utf-8")
    monkeypatch.setattr(broker, "SHARED", shared)

    prompt = broker._manifest_prompt([_entry(inside), _entry(outside)])

    assert str(inside.resolve()) in prompt
    assert str(outside.resolve()) in prompt
    assert "[OUTSIDE SHARED]" in prompt
