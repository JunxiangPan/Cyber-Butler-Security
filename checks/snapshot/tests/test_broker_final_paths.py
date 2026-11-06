"""Final business paths: email challenge, send wait, approval-only verify."""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


class Snap:
    is_directory = False
    identity = (0, 0, 1, 2)

    def assert_unchanged(self): return None
    def close(self): return None


class Event:
    def __init__(self): self.done = False
    def wait(self, timeout): return self.done
    def set(self): self.done = True


def _setup(monkeypatch, tmp_path):
    broker.broker_state._pending = None
    broker.broker_state._verify_locked_until = 0
    broker.broker_state._global_failures = 0
    broker.broker_state._global_lock_until = 0
    monkeypatch.setattr(broker, "_is_uninstalling", lambda: False)
    monkeypatch.setattr(broker, "_is_verification_locked", lambda: False)
    monkeypatch.setattr(broker, "_critical_integrity_hit", lambda target: False)
    monkeypatch.setattr(broker, "_rule_tampering_hit", lambda target: False)
    monkeypatch.setattr(broker, "classify", lambda action, target: "totp")
    monkeypatch.setattr(broker, "_prepare_snapshots", lambda *a: (Snap(), Snap()))
    monkeypatch.setattr(broker, "_snapshot_summary", lambda *a: "s")
    monkeypatch.setattr(broker, "_path_summary", lambda *a: "p")
    monkeypatch.setattr(broker, "_target_mode", lambda *a: "replace")
    monkeypatch.setattr(broker, "approval_preview", SimpleNamespace(build_preview=lambda *a, **k: {"x": 1}, format_preview=lambda *a, **k: "p"))
    monkeypatch.setattr(broker.injection_audit, "warning", lambda: "")
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    monkeypatch.setattr(broker, "execute", lambda request: broker.ExecutionResult(200, "ok"))
    monkeypatch.setattr(broker, "_assert_snapshots_current", lambda request: None)


def test_email_challenge_success(monkeypatch, tmp_path) -> None:
    _setup(monkeypatch, tmp_path)
    target = tmp_path / "x.txt"; target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "_approval_channel", lambda: "email")
    monkeypatch.setattr(broker, "_admin_email", lambda: "owner@example.com")
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {})
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a: None)
    monkeypatch.setattr(broker.threading, "Thread", lambda *a, **k: SimpleNamespace(start=lambda: None))
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 200 and body["channel"] == "email"
    broker.broker_state._pending = None


def test_send_timeout(monkeypatch, tmp_path) -> None:
    _setup(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "_approval_channel", lambda: "qq")
    monkeypatch.setattr(broker, "_canonical_manifest", lambda manifest: manifest)
    monkeypatch.setattr(broker, "_manifest_prompt", lambda manifest: "prompt")
    monkeypatch.setattr(broker.threading, "Event", Event)
    monkeypatch.setattr(broker.threading, "Thread", lambda *a, **k: SimpleNamespace(start=lambda: None))
    status, _body = broker.run_request({"action": "send", "manifest": [{"path": "http://x", "kind": "url"}]})
    assert status == 408
    broker.broker_state._pending = None


def test_approval_only_verify_and_send_manifest_success(monkeypatch, tmp_path) -> None:
    _setup(monkeypatch, tmp_path)
    target = tmp_path / "x.txt"; target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "totp")
    broker.broker_state._pending = {"id": "approve-1", "action": "delete", "target": str(target), "deadline": 10**18, "attempts": 0, "channel": "webui", "approval_only": True, "manifest": None, "_snapshot": Snap(), "target_summary": "p", "source_summary": ""}
    status, _body = broker.run_verify({"id": "approve-1", "code": "1"})
    assert status == 200
    broker.broker_state._pending = {"id": "send-ok", "action": "send", "target": "http://x", "deadline": 10**18, "attempts": 0, "channel": "webui", "approval_only": False, "manifest": [{"path": "http://x", "kind": "url"}]}
    monkeypatch.setattr(broker, "_canonical_manifest", lambda manifest: manifest)
    monkeypatch.setattr(broker, "_manifest_equal", lambda left, right: True)
    broker._send_results["send-ok"] = True
    status, _body = broker.run_verify({"id": "send-ok", "code": "1"})
    assert status == 200
