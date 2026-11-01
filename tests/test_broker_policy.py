"""Policy tests for the broker's allow/totp/deny split."""

from __future__ import annotations

from pathlib import Path

import broker


def setup_function() -> None:
    broker._pending = None
    broker._send_events.clear()
    broker._send_results.clear()
    broker._last_request_at = 0.0
    with broker._bypass_lock:
        broker._bypass_tokens.clear()
    with broker._approval_lock:
        broker._approval_states.clear()


def _roots(tmp_path: Path):
    tmp = tmp_path / "tmp"
    memory = tmp_path / "memory"
    vault = tmp_path / "vault"
    shared = tmp_path / "shared"
    for path in (tmp, memory, vault, shared):
        path.mkdir(parents=True, exist_ok=True)
    return tmp, memory, vault, shared


def test_classify_tmp_is_auto_allowed(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)

    assert broker.classify("delete", str(tmp / "a.txt")) == "allow"
    assert broker.classify("write_file", str(tmp / "a.txt")) == "allow"


def test_classify_memory_requires_totp(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)

    assert broker.classify("write_file", str(memory / "facts.db")) == "totp"
    assert broker.classify("delete", str(memory / "facts.db")) == "totp"


def test_classify_vault_is_denied(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)

    assert broker.classify("delete", str(vault / "totp_secret.dpapi")) == "deny"
    assert broker.classify("write_file", str(vault / "x")) == "deny"


def test_tmp_write_file_executes_without_pending(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    target = tmp / "note.txt"

    status, body = broker.run_request(
        {"action": "write_file", "target": str(target), "content": "auto"}
    )

    assert status == 200
    assert body["auto_executed"] is True
    assert target.read_text(encoding="utf-8") == "auto"
    assert broker._pending is None
    assert audit.exists()


def test_memory_write_file_creates_totp_pending(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    target = memory / "facts.db"

    status, body = broker.run_request(
        {"action": "write_file", "target": str(target), "content": "secret"}
    )

    assert status == 200
    assert body.get("id")
    assert broker._pending is not None
    assert broker._pending["action"] == "write_file"
    assert broker._pending["content"] == "secret"
    assert not target.exists()


def test_shared_create_is_auto_but_existing_write_needs_totp(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)

    new_file = shared / "new.txt"
    assert broker.classify("write_file", str(new_file)) == "allow"
    new_file.write_text("old", encoding="utf-8")
    assert broker.classify("write_file", str(new_file)) == "totp"
    assert broker.classify("delete", str(new_file)) == "totp"
    assert broker.classify("overwrite", str(new_file)) == "totp"


def test_bypass_is_scoped_to_action_and_directory(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)

    first = shared / "a.txt"
    second = shared / "b.txt"
    other_dir = shared / "sub" / "c.txt"
    first.write_text("x", encoding="utf-8")
    second.write_text("x", encoding="utf-8")

    token = broker._issue_bypass("delete", str(first))
    assert token is not None
    assert broker._consume_bypass(token["token"], "delete", str(second)) is not None
    assert broker._consume_bypass(token["token"], "delete", str(other_dir)) is None
    assert broker._consume_bypass(token["token"], "overwrite", str(second)) is None


def test_bypass_expires(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    first = shared / "a.txt"
    first.write_text("x", encoding="utf-8")

    token = broker._issue_bypass("delete", str(first))
    assert token is not None
    with broker._bypass_lock:
        broker._bypass_tokens[token["token"]]["expires"] = 0
    assert broker._consume_bypass(token["token"], "delete", str(first)) is None


def test_request_with_bypass_executes_and_audits(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    audit = tmp_path / "audit.jsonl"
    quarantine = tmp_path / "quarantine"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "QUARANTINE", quarantine)
    target = shared / "old.txt"
    target.write_text("x", encoding="utf-8")
    issued = broker._issue_bypass("delete", str(target))
    assert issued is not None

    status, body = broker.run_request({
        "action": "delete",
        "target": str(target),
        "reason": "batch cleanup",
        "bypass_token": issued["token"],
    })

    assert status == 200
    assert body["bypassed"] is True
    assert not target.exists()
    audit_text = audit.read_text(encoding="utf-8")
    assert "30s_session" in audit_text
    assert "Bypassed via 30s Session Token" in audit_text


def test_shared_new_file_write_is_auto(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    target = shared / "created.txt"

    status, body = broker.run_request({
        "action": "write_file",
        "target": str(target),
        "content": "new",
    })

    assert status == 200
    assert body["auto_executed"] is True
    assert target.read_text(encoding="utf-8") == "new"
    assert broker._pending is None


def test_verify_issues_scoped_bypass_token(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    monkeypatch.setattr(broker, "verify_code", lambda code: "totp")
    monkeypatch.setattr(broker, "execute", lambda request: (True, "ok"))
    target = shared / "a.txt"
    target.write_text("x", encoding="utf-8")
    broker._pending = {
        "id": "req-1",
        "action": "delete",
        "target": str(target),
        "target_summary": broker._path_summary(str(target)),
        "channel": "",
        "deadline": broker.time.monotonic() + 30,
        "attempts": 0,
    }

    status, body = broker.run_verify({"code": "123456", "bypass_seconds": 30})

    assert status == 200
    assert body["ok"] is True
    token = body.get("bypass_token")
    assert token
    assert broker._consume_bypass(token, "delete", str(target)) is not None
    assert broker._consume_bypass(token, "delete", str(shared / "b.txt")) is not None
    assert broker._consume_bypass(token, "delete", str(shared / "sub" / "c.txt")) is None
    assert "bypass_issued" in audit.read_text(encoding="utf-8")


def _approval_roots(monkeypatch, tmp_path):
    tmp, memory, vault, shared = _roots(tmp_path)
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    return tmp, memory, vault, shared, audit


def test_approval_only_auto_allowed_does_not_execute(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared, audit = _approval_roots(monkeypatch, tmp_path)
    target = shared / "new.txt"

    status, body = broker.run_request({
        "action": "write_file",
        "target": str(target),
        "content": "dsh will write this",
        "approval_only": True,
    })

    assert status == 200
    assert body["status"] == "allowed"
    assert body["approval_only"] is True
    assert not target.exists()


def test_approval_only_totp_creates_pending_state(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared, audit = _approval_roots(monkeypatch, tmp_path)
    target = memory / "facts.db"

    status, body = broker.run_request({
        "action": "write_file",
        "target": str(target),
        "content": "dsh will write this",
        "approval_only": True,
    })

    assert status == 200
    assert body["status"] == "requires_totp"
    assert body["challenge_id"] == body["id"]
    state = broker.get_approval_status(body["challenge_id"])
    assert state[0] == 200
    assert state[1]["status"] == "pending"
    assert not target.exists()


def test_approval_only_verify_approves_without_execute(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared, audit = _approval_roots(monkeypatch, tmp_path)
    target = memory / "facts.db"
    target.write_text("old", encoding="utf-8")
    executed = {"called": False}

    def fake_execute(request):
        executed["called"] = True
        return True, "must not run"

    monkeypatch.setattr(broker, "verify_code", lambda code: "totp")
    monkeypatch.setattr(broker, "execute", fake_execute)
    broker._pending = {
        "id": "approval-1",
        "action": "write_file",
        "target": str(target),
        "target_summary": broker._path_summary(str(target)),
        "source_summary": "",
        "deadline": broker.time.monotonic() + 30,
        "attempts": 0,
        "channel": "qq",
        "approval_only": True,
    }

    status, body = broker.run_verify({"code": "123456"})

    assert status == 200
    assert body["status"] == "approved"
    assert body["approval_only"] is True
    assert executed["called"] is False
    assert broker.get_approval_status("approval-1")[1]["status"] == "approved"
    assert target.read_text(encoding="utf-8") == "old"


def test_approval_only_endpoint_adapter(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared, audit = _approval_roots(monkeypatch, tmp_path)
    target = shared / "new.txt"

    status, body = broker.run_approval_request({
        "action": "write_file",
        "target": str(target),
        "content": "via adapter",
    })

    assert status == 200
    assert body["status"] == "allowed"
    assert not target.exists()
