"""Minimal platform-API exception tests backing coverage allowlist entries."""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


def test_job_object_is_safe_on_non_windows(monkeypatch) -> None:
    monkeypatch.setattr(broker.os, "name", "posix")
    assert broker.initialize_job_object() is False


def test_token_acl_failure_is_fail_closed(monkeypatch, tmp_path: Path) -> None:
    token = tmp_path / "broker_token.txt"
    monkeypatch.setattr(broker, "TOKEN_FILE", token)
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.setenv("CBS_SERVICE_USER", "CyberButlerSvc")
    monkeypatch.setattr(
        broker.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(returncode=1, stdout="", stderr="denied"),
    )
    try:
        broker.ensure_token()
    except RuntimeError as exc:
        assert "ACL failed" in str(exc)
    else:
        raise AssertionError("token ACL failure must be fail-closed")



def test_audit_key_guard_fails_closed(monkeypatch):
    import broker
    import audit_chain

    monkeypatch.delenv("CBS_AUDIT_HMAC_KEY", raising=False)
    monkeypatch.setenv("CBS_AUDIT_KEY_FILE", r"C:\does-not-exist\audit.key")
    monkeypatch.setattr(audit_chain, "_KEY_CACHE", None)
    try:
        broker._require_audit_key()
    except SystemExit as exc:
        assert "audit HMAC key unavailable" in str(exc)
    else:
        raise AssertionError("missing audit key did not fail closed")
