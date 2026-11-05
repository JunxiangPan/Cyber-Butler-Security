"""SMTP/IMAP failure paths for the broker email approval channel."""
from __future__ import annotations

import socket
import sys
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402
import email_approval  # noqa: E402

CONFIG = {
    "smtp_host": "smtp.example",
    "smtp_port": 465,
    "smtp_user": "owner@example.com",
    "smtp_pass": "secret",
    "smtp_from": "owner@example.com",
    "approval_to": "owner@example.com",
    "imap_host": "imap.example",
    "imap_port": 993,
    "imap_user": "owner@example.com",
    "imap_pass": "secret",
    "allowed_sender": "owner@example.com",
}


def test_smtp_timeout_is_raised_to_caller() -> None:
    with patch("email_approval.smtplib.SMTP_SSL", side_effect=socket.timeout("timeout")):
        try:
            email_approval.send_email(CONFIG, "subject", "body")
        except socket.timeout:
            pass
        else:
            raise AssertionError("send_email must propagate SMTP timeout")


def test_email_result_swallows_smtp_failure() -> None:
    with patch("email_approval.send_email", side_effect=ConnectionRefusedError("refused")):
        broker._email_result(CONFIG, {"challenge": "ABCD", "action": "delete", "target": "x"}, "ok")
    # No exception means the failure was logged and contained.


def test_imap_authentication_failure_propagates() -> None:
    with patch("email_approval.imaplib.IMAP4_SSL", side_effect=email_approval.imaplib.IMAP4.error("auth")):
        try:
            email_approval.poll_once(CONFIG, "ABCD")
        except email_approval.imaplib.IMAP4.error:
            pass
        else:
            raise AssertionError("poll_once must propagate IMAP authentication failure")


def test_email_watch_handles_expired_pending(monkeypatch) -> None:
    monkeypatch.setattr(email_approval, "load_config", lambda: CONFIG)
    broker.broker_state._pending = {
        "id": "expired-email", "channel": "email", "deadline": 0,
        "challenge": "ABCD", "action": "delete", "target": "x",
    }
    try:
        broker.email_watch("expired-email")
    finally:
        broker.broker_state._pending = None


def test_email_watch_retries_then_executes(monkeypatch, tmp_path) -> None:
    calls = {"n": 0}

    def poll(config, challenge):
        calls["n"] += 1
        if calls["n"] == 1:
            raise socket.timeout("temporary")
        return ("owner@example.com", "ABCD", "123456")

    monkeypatch.setattr(email_approval, "load_config", lambda: CONFIG)
    monkeypatch.setattr(email_approval, "poll_once", poll)
    monkeypatch.setattr(email_approval, "sender_allowed", lambda header, allowed: True)
    monkeypatch.setattr(broker.time, "sleep", lambda seconds: None)
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "totp")
    monkeypatch.setattr(broker, "_assert_snapshots_current", lambda request: None)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    monkeypatch.setattr(broker, "execute", lambda request: broker.ExecutionResult(200, "ok"))
    monkeypatch.setattr(broker, "_email_result", lambda config, request, result: None)
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    broker.broker_state._pending = {
        "id": "email-retry", "channel": "email", "deadline": 10**9,
        "challenge": "ABCD", "action": "delete", "target": str(tmp_path / "x"),
        "source": "", "reason": "", "attempts": 0, "_snapshot": None,
        "_source_snapshot": None, "target_summary": broker._path_summary(str(tmp_path / "x")),
    }
    try:
        broker.email_watch("email-retry")
    finally:
        broker.broker_state._pending = None
    assert calls["n"] == 2
