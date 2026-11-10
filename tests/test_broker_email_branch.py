"""P0-4: email approval branch and audit-result paths."""
from __future__ import annotations

import json
from pathlib import Path

import broker


def _config(path: Path, **values) -> None:
    path.write_text(json.dumps(values), encoding="utf-8")


def test_email_challenge_and_missing_admin(monkeypatch, tmp_path: Path) -> None:
    shared = tmp_path / "shared"
    shared.mkdir()
    config = tmp_path / "config.json"
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "MEMORY_ROOTS", ())
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    broker._pending = None
    _config(config, approval_channel="email")
    target = shared / "mail.txt"
    target.write_text("mail", encoding="utf-8")
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 503 and "admin_email" in body["error"]

    _config(config, approval_channel="email", admin_email="qa@example.test")
    sent = []
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {"allowed_sender": "qa@example.test"})
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a, **k: sent.append(a))
    monkeypatch.setattr(broker, "email_watch", lambda _id: None)
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 200 and body["channel"] == "email"
    assert sent


def test_email_send_failure(monkeypatch, tmp_path: Path) -> None:
    shared = tmp_path / "shared"
    shared.mkdir()
    config = tmp_path / "config.json"
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "MEMORY_ROOTS", ())
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    broker._pending = None
    _config(config, approval_channel="email", admin_email="qa@example.test")
    target = shared / "mail.txt"
    target.write_text("mail", encoding="utf-8")
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {})
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("smtp down")))
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 502 and "email challenge" in body["error"]


def test_email_watch_executes_once(monkeypatch, tmp_path: Path) -> None:
    shared = tmp_path / "shared"
    shared.mkdir()
    target = shared / "watch.txt"
    target.write_text("watch", encoding="utf-8")
    broker._pending = {
        "id": "email-1",
        "channel": "email",
        "deadline": broker.time.monotonic() + 60,
        "challenge": "challenge-1",
        "target": str(target),
        "target_summary": broker._path_summary(str(target)),
        "action": "delete",
        "_snapshot": None,
        "_source_snapshot": None,
    }
    results = []
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {"allowed_sender": "qa@example.test"})
    monkeypatch.setattr(broker.email_approval, "poll_once", lambda *_a: ("qa@example.test", "challenge-1", "123456"))
    monkeypatch.setattr(broker.email_approval, "sender_allowed", lambda *_a: True)
    monkeypatch.setattr(broker, "verify_code", lambda _code: "totp")
    monkeypatch.setattr(broker, "_assert_snapshots_current", lambda _request: None)
    monkeypatch.setattr(broker, "execute", lambda _request: (True, "ok"))
    monkeypatch.setattr(broker, "_email_result", lambda _config, _request, result: results.append(result))
    broker.email_watch("email-1")
    assert broker._pending is None
    assert results == ["ok"]


def test_email_watch_config_failure(monkeypatch, tmp_path: Path) -> None:
    broker._pending = {"id": "email-fail", "channel": "email", "deadline": broker.time.monotonic() + 60}
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: (_ for _ in ()).throw(RuntimeError("no config")))
    broker.email_watch("email-fail")
    assert broker._pending is None


def test_email_watch_timeout_sends_notice(monkeypatch, tmp_path: Path) -> None:
    broker._pending = {"id": "email-timeout", "channel": "email", "deadline": broker.time.monotonic() - 1, "challenge": "c"}
    sent = []
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {"allowed_sender": "qa@example.test"})
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a, **k: sent.append(a))
    broker.email_watch("email-timeout")
    assert broker._pending is None


def test_email_watch_invalid_sender_then_timeout(monkeypatch, tmp_path: Path) -> None:
    broker._pending = {
        "id": "email-sender",
        "channel": "email",
        "deadline": broker.time.monotonic() + 0.2,
        "challenge": "c",
        "target": str(tmp_path / "x"),
        "action": "delete",
    }
    sent = []
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {"allowed_sender": "qa@example.test"})
    monkeypatch.setattr(broker.email_approval, "poll_once", lambda *_a: ("evil@example.test", "c", "123456"))
    monkeypatch.setattr(broker.email_approval, "sender_allowed", lambda *_a: False)
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a, **k: sent.append(a))
    broker.email_watch("email-sender")
    assert broker._pending is None


def test_email_watch_poll_exception_then_timeout(monkeypatch, tmp_path: Path) -> None:
    broker._pending = {
        "id": "email-poll",
        "channel": "email",
        "deadline": broker.time.monotonic() + 0.2,
        "challenge": "c",
        "target": str(tmp_path / "x"),
        "action": "delete",
    }
    sent = []
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {"allowed_sender": "qa@example.test"})
    monkeypatch.setattr(broker.email_approval, "poll_once", lambda *_a: (_ for _ in ()).throw(RuntimeError("imap")))
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a, **k: sent.append(a))
    monkeypatch.setattr(broker.time, "sleep", lambda _s: None)
    broker.email_watch("email-poll")
    assert broker._pending is None


def test_email_watch_challenge_mismatch_then_timeout(monkeypatch, tmp_path: Path) -> None:
    broker._pending = {
        "id": "email-mismatch", "channel": "email",
        "deadline": broker.time.monotonic() + 0.2,
        "challenge": "expected", "target": str(tmp_path / "x"), "action": "delete",
    }
    sent = []
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {"allowed_sender": "qa@example.test"})
    monkeypatch.setattr(broker.email_approval, "poll_once", lambda *_a: ("qa@example.test", "wrong", "123456"))
    monkeypatch.setattr(broker.email_approval, "sender_allowed", lambda *_a: True)
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a, **k: sent.append(a))
    broker.email_watch("email-mismatch")
    assert broker._pending is None


def test_email_watch_invalid_totp_then_timeout(monkeypatch, tmp_path: Path) -> None:
    broker._pending = {
        "id": "email-bad", "channel": "email", "deadline": broker.time.monotonic() + 0.2,
        "challenge": "c", "target": str(tmp_path / "x"), "action": "delete",
    }
    sent = []
    monkeypatch.setattr(broker.email_approval, "load_config", lambda: {"allowed_sender": "qa@example.test"})
    monkeypatch.setattr(broker.email_approval, "poll_once", lambda *_a: ("qa@example.test", "c", "000000"))
    monkeypatch.setattr(broker.email_approval, "sender_allowed", lambda *_a: True)
    monkeypatch.setattr(broker, "verify_code", lambda _c: None)
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a, **k: sent.append(a))
    broker.email_watch("email-bad")
    assert broker._pending is None
