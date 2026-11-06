"""State-machine tests for broker.run_request."""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


class Snap:
    is_directory = False
    identity = (0, 0, 0, 0)

    def assert_unchanged(self):
        return None

    def close(self):
        return None


def _setup(monkeypatch, tmp_path: Path):
    broker.broker_state._pending = None
    broker.broker_state._verify_locked_until = 0
    monkeypatch.setattr(broker, "_is_uninstalling", lambda: False)
    monkeypatch.setattr(broker, "_is_verification_locked", lambda: False)
    monkeypatch.setattr(broker, "_critical_integrity_hit", lambda target: False)
    monkeypatch.setattr(broker, "_rule_tampering_hit", lambda target: False)
    monkeypatch.setattr(broker, "classify", lambda action, target: "allow")
    monkeypatch.setattr(broker, "_prepare_snapshots", lambda action, target, source: (Snap(), Snap()))
    monkeypatch.setattr(broker, "_snapshot_summary", lambda snap, target: "summary")
    monkeypatch.setattr(broker, "_path_summary", lambda target: "path")
    monkeypatch.setattr(broker, "_target_mode", lambda action, target: "replace")
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    monkeypatch.setattr(broker, "execute", lambda request: broker.ExecutionResult(200, "ok"))
    monkeypatch.setattr(broker, "_approval_channel", lambda: "webui")
    monkeypatch.setattr(broker, "_admin_email", lambda: "owner@example.com")
    monkeypatch.setattr(broker.approval_preview, "build_preview", lambda *a, **k: {"action": "x"})
    monkeypatch.setattr(broker.approval_preview, "format_preview", lambda *a, **k: "preview")
    monkeypatch.setattr(broker.injection_audit, "warning", lambda: "")


def test_precondition_and_payload_guards(monkeypatch, tmp_path: Path) -> None:
    _setup(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "_is_uninstalling", lambda: True)
    assert broker.run_request({"action": "delete", "target": "x"})[0] == 503
    monkeypatch.setattr(broker, "_is_uninstalling", lambda: False)
    monkeypatch.setattr(broker, "_is_verification_locked", lambda: True)
    assert broker.run_request({"action": "delete", "target": "x"})[0] == 429
    monkeypatch.setattr(broker, "_is_verification_locked", lambda: False)
    assert broker.run_request({"action": "send", "target": "x", "approval_only": True})[0] == 400
    directory = tmp_path / "dir"
    directory.mkdir()
    assert broker.run_request({"action": "delete", "target": str(directory)})[0] == 400
    assert broker.run_request({"action": "unknown", "target": "x"})[0] == 400
    monkeypatch.setattr(broker, "_critical_integrity_hit", lambda target: True)
    assert broker.run_request({"action": "delete", "target": "x"})[0] == 403


def test_deny_and_snapshot_binding_failure(monkeypatch, tmp_path: Path) -> None:
    _setup(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "classify", lambda action, target: "deny")
    assert broker.run_request({"action": "delete", "target": "x"})[0] == 403
    monkeypatch.setattr(broker, "classify", lambda action, target: "allow")
    monkeypatch.setattr(broker, "_prepare_snapshots", lambda *a: (_ for _ in ()).throw(OSError("no")))
    assert broker.run_request({"action": "delete", "target": "x"})[0] == 409


def test_auto_allow_and_approval_only(monkeypatch, tmp_path: Path) -> None:
    _setup(monkeypatch, tmp_path)
    target = tmp_path / "x.txt"
    target.write_text("x", encoding="utf-8")
    status, body = broker.run_request({"action": "delete", "target": str(target), "approval_only": True})
    assert status == 200 and body["approval_only"] is True
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 200 and body["auto_executed"] is True


def test_pending_conflict_and_webui(monkeypatch, tmp_path: Path) -> None:
    _setup(monkeypatch, tmp_path)
    target = tmp_path / "x.txt"
    target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "classify", lambda action, target: "totp")
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 200 and body["status"] == "requires_totp"
    assert broker.broker_state._pending is not None
    status, body = broker.run_request({"action": "delete", "target": str(target), "approval_only": True})
    assert status == 409
    broker.broker_state._pending = None


def test_email_without_admin_and_send_failures(monkeypatch, tmp_path: Path) -> None:
    _setup(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "_approval_channel", lambda: "email")
    monkeypatch.setattr(broker, "_admin_email", lambda: "")
    target = tmp_path / "x.txt"
    target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "classify", lambda action, target: "totp")
    assert broker.run_request({"action": "delete", "target": str(target)})[0] == 503
    broker.broker_state._pending = None
    monkeypatch.setattr(broker, "_approval_channel", lambda: "qq")
    monkeypatch.setattr(broker, "send_qq", lambda text: False)
    assert broker.run_request({"action": "delete", "target": str(target)})[0] == 502
    broker.broker_state._pending = None
