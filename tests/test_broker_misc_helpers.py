"""P0-4: miscellaneous Broker branches."""
from __future__ import annotations

import json
import threading
from pathlib import Path

import broker


def test_notify_and_fail_send_wait(monkeypatch) -> None:
    called = []
    monkeypatch.setattr(broker, "send_qq", lambda text: called.append(text) or True)
    broker._notify_async("hello")
    for _ in range(20):
        if called:
            break
        threading.Event().wait(0.01)
    assert called == ["hello"]
    event = threading.Event()
    broker._send_events["x"] = event
    broker._send_results["x"] = True
    broker._fail_send_wait("x")
    assert event.is_set() and broker._send_results["x"] is False
    broker._send_events.pop("x", None)
    broker._send_results.pop("x", None)


def test_admin_email_and_channel(monkeypatch, tmp_path: Path) -> None:
    config = tmp_path / "broker_config.json"
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    config.write_text(json.dumps({"admin_email": "qa@example.test", "approval_channel": "email"}), encoding="utf-8")
    assert broker._admin_email() == "qa@example.test"
    assert broker._approval_channel() == "email"
    config.write_text(json.dumps({"approval_channel": "bogus"}), encoding="utf-8")
    assert broker._approval_channel() == "webui"


def test_manifest_prompt_and_close_snapshots(monkeypatch, tmp_path: Path) -> None:
    shared = tmp_path / "shared"
    shared.mkdir()
    monkeypatch.setattr(broker, "SHARED", shared)
    manifest = [{"kind": "file", "path": str(shared / "a.txt"), "size": 1, "sha256": "a" * 64}]
    text = broker._manifest_prompt(manifest)
    assert "a.txt" in text and "sha256=" in text
    broker._close_request_snapshots(None)


def test_approval_state_helpers() -> None:
    broker._approval_states.clear()
    broker._set_approval_state("state-1", "pending", True)
    status, body = broker.get_approval_status("state-1")
    assert status == 200 and body["status"] == "pending"
    broker._approval_states.clear()


def test_secret_paths_and_snapshot_summary(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "SECRET_FILE", tmp_path / "secret.dpapi")
    monkeypatch.setattr(broker, "RECOVERY_FILE", tmp_path / "recovery.json")
    assert broker._secret_file() == tmp_path / "secret.dpapi"
    assert broker._recovery_file() == tmp_path / "recovery.json"
    assert "missing" in broker._snapshot_summary(None, str(tmp_path / "none"))


def test_lock_and_uninstall_helpers(monkeypatch) -> None:
    monkeypatch.setattr(broker, "_verify_locked_until", 0.0)
    monkeypatch.setattr(broker, "_global_lock_until", 0.0)
    assert broker._is_verification_locked() is False
    monkeypatch.setenv("CBS_IS_UNINSTALLING", "1")
    assert broker._is_uninstalling() is True
    monkeypatch.delenv("CBS_IS_UNINSTALLING", raising=False)
    broker._global_failures = 0
    broker._global_lock_until = 0.0
    broker._record_global_failure()
    assert broker._global_failures >= 1


def test_resolve_helpers(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("CBS_WORKSPACE", str(tmp_path))
    assert broker._resolve_shared() == tmp_path
    assert isinstance(broker._resolve_umo(), str)
