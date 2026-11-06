"""Final email/QQ send failure branches."""
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


def _setup(monkeypatch, tmp_path):
    broker.broker_state._pending = None
    monkeypatch.setattr(broker, "_is_uninstalling", lambda: False)
    monkeypatch.setattr(broker, "_is_verification_locked", lambda: False)
    monkeypatch.setattr(broker, "_critical_integrity_hit", lambda target: False)
    monkeypatch.setattr(broker, "_rule_tampering_hit", lambda target: False)
    monkeypatch.setattr(broker, "classify", lambda action, target: "totp")
    monkeypatch.setattr(broker, "_prepare_snapshots", lambda *a: (Snap(), Snap()))
    monkeypatch.setattr(broker, "_snapshot_summary", lambda *a: "s")
    monkeypatch.setattr(broker, "_path_summary", lambda *a: "p")
    monkeypatch.setattr(broker, "_target_mode", lambda *a: "replace")
    monkeypatch.setattr(broker, "approval_preview", SimpleNamespace(build_preview=lambda *a, **k: {}, format_preview=lambda *a, **k: "p"))
    monkeypatch.setattr(broker.injection_audit, "warning", lambda: "")
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    monkeypatch.setattr(broker, "execute", lambda request: broker.ExecutionResult(200, "ok"))
    monkeypatch.setattr(broker, "_assert_snapshots_current", lambda request: None)


def test_email_send_failure_returns_502(monkeypatch, tmp_path) -> None:
    _setup(monkeypatch, tmp_path)
    target = tmp_path / "x.txt"; target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "_approval_channel", lambda: "email")
    monkeypatch.setattr(broker, "_admin_email", lambda: "owner@example.com")
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {})
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a: (_ for _ in ()).throw(OSError("smtp")))
    monkeypatch.setattr(broker.threading, "Thread", lambda *a, **k: SimpleNamespace(start=lambda: None))
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 502 and body["ok"] is False
    broker.broker_state._pending = None


def test_qq_send_failure_returns_502(monkeypatch, tmp_path) -> None:
    _setup(monkeypatch, tmp_path)
    target = tmp_path / "x.txt"; target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "_approval_channel", lambda: "qq")
    monkeypatch.setattr(broker, "send_qq", lambda text: False)
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 502 and body["ok"] is False
    broker.broker_state._pending = None


def test_reset_recovery_without_win32crypt(monkeypatch) -> None:
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "recovery")
    monkeypatch.setattr(broker, "win32crypt", None)
    status, body = broker.reset_totp_with_recovery("ABCD1234")
    assert status == 503 and body["ok"] is False
