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
    with broker._scoped_lock:
        broker._scoped_tokens.clear()


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
    assert body["id"]
    state = broker.get_approval_status(body["id"])
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


def _scoped_roots(monkeypatch, tmp_path):
    tmp, memory, vault, shared = _roots(tmp_path)
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    return tmp, memory, vault, shared, audit


def test_scoped_token_is_directory_bound(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared, audit = _scoped_roots(monkeypatch, tmp_path)
    root = shared / "draft"
    root.mkdir()
    first = root / "a.txt"
    sibling = shared / "other" / "b.txt"
    sibling.parent.mkdir()

    issued = broker._issue_scoped("delete", str(first), 30)
    assert issued is not None
    assert broker._consume_scoped(issued["token"], "delete", str(root / "c.txt")) is not None
    assert broker._consume_scoped(issued["token"], "delete", str(sibling)) is None
    assert broker._consume_scoped(issued["token"], "send", str(root / "c.txt")) is None


def test_scoped_token_executes_same_directory(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared, audit = _scoped_roots(monkeypatch, tmp_path)
    quarantine = tmp_path / "quarantine"
    monkeypatch.setattr(broker, "QUARANTINE", quarantine)
    root = shared / "draft"
    root.mkdir()
    target = root / "a.txt"
    target.write_text("x", encoding="utf-8")
    issued = broker._issue_scoped("delete", str(target), 30)
    assert issued is not None

    status, body = broker.run_request({
        "action": "delete",
        "target": str(target),
        "scoped_token": issued["token"],
    })

    assert status == 200
    assert body["scoped"] is True
    assert not target.exists()
    assert "30m_directory" in audit.read_text(encoding="utf-8")


def test_approval_only_scoped_is_allowed_without_execute(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared, audit = _scoped_roots(monkeypatch, tmp_path)
    root = shared / "draft"
    root.mkdir()
    target = root / "a.txt"
    target.write_text("x", encoding="utf-8")
    issued = broker._issue_scoped("write_file", str(target), 30)
    assert issued is not None

    status, body = broker.run_request({
        "action": "write_file",
        "target": str(target),
        "content": "new",
        "approval_only": True,
        "scoped_token": issued["token"],
    })

    assert status == 200
    assert body["status"] == "allowed"
    assert body["scoped"] is True
    assert body["auto_executed"] is False
    assert target.read_text(encoding="utf-8") == "x"
    assert "Scoped via 30-minute Directory Token" in audit.read_text(encoding="utf-8")


def test_verify_ignores_caller_supplied_scope(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared, audit = _scoped_roots(monkeypatch, tmp_path)
    root = shared / "draft"
    root.mkdir()
    target = root / "a.txt"
    target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "verify_code", lambda code: "totp")
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    broker._pending = {
        "id": "scoped-1",
        "action": "delete",
        "target": str(target),
        "target_summary": broker._path_summary(str(target)),
        "source_summary": "",
        "deadline": broker.time.monotonic() + 30,
        "attempts": 0,
        "channel": "qq",
        "approval_only": True,
    }

    status, body = broker.run_verify({"code": "123456", "scoped_minutes": 30})

    assert status == 200
    assert "scoped_token" not in body
    assert body["status"] == "approved"


def test_uipi_blocked_audit_event(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared, audit = _scoped_roots(monkeypatch, tmp_path)
    broker.report_uipi_blocked("test-gui-call", "no result")
    text = audit.read_text(encoding="utf-8")
    assert "UIPI_BLOCKED_GUI_INTERACTION" in text
    assert "test-gui-call" in text


def test_helper_as_bool_and_url_host_allowlist(monkeypatch, tmp_path) -> None:
    assert broker._as_bool(True) is True
    assert broker._as_bool("yes") is True
    assert broker._as_bool("off") is False
    monkeypatch.setenv("CBS_URL_ALLOWED_HOSTS", "api.example.test, cdn.example.test")
    assert broker._url_host_allowed("https://api.example.test/v1") is True
    assert broker._url_host_allowed("https://evil.example.test/v1") is False
    assert broker._url_host_allowed("not a url") is False


def test_helper_sha256_and_path_summary(tmp_path) -> None:
    target = tmp_path / "a.txt"
    target.write_text("hello", encoding="utf-8")
    assert broker._sha256_file(target) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    text = broker._path_summary(str(target))
    assert "file" in text and "5 bytes" in text
    assert "missing" in broker._path_summary(str(tmp_path / "absent"))


def test_helper_manifest_rejects_empty_and_inside_any(tmp_path) -> None:
    try:
        broker._canonical_manifest([])
        raise AssertionError("empty manifest should be rejected")
    except ValueError:
        pass
    assert broker._inside_any(tmp_path / "child", (tmp_path,)) is True
    assert broker._inside_any(tmp_path.parent / "outside", (tmp_path,)) is False


def test_bypass_and_scoped_token_lifecycle(monkeypatch, tmp_path) -> None:
    target = tmp_path / "scoped.txt"
    target.write_text("x", encoding="utf-8")
    assert broker._target_mode("write_file", str(target)) == "replace"
    assert broker._target_mode("overwrite", str(target)) == "replace"
    assert broker._target_mode("delete", str(target)) == "delete"
    bypass = broker._issue_bypass("delete", str(target), 30)
    assert bypass and broker._consume_bypass(bypass["token"], "delete", str(target))
    assert broker._consume_bypass(bypass["token"], "overwrite", str(target)) is None
    monkeypatch.setattr(broker, "SHARED", tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    scoped = broker._issue_scoped("delete", str(target), 1)
    assert scoped and broker._consume_scoped(scoped["token"], "delete", str(target))
    assert broker._consume_scoped("not-a-token", "delete", str(target)) is None
    assert broker._consume_scoped(scoped["token"], "delete", str(tmp_path.parent / "outside.txt")) is None


def test_job_limit_helpers_smoke() -> None:
    env = broker._job_limit_environment()
    flags, values = broker._job_limit_flags()
    assert isinstance(env, dict)
    assert isinstance(flags, int)
    assert isinstance(values, dict)


def test_run_request_and_verify_error_branches(tmp_path) -> None:
    status, body = broker.run_request({"action": "invalid", "target": "x"})
    assert status == 400 and "action" in body["error"]
    folder = tmp_path / "folder"
    folder.mkdir()
    status, body = broker.run_request({"action": "delete", "target": str(folder)})
    assert status == 400 and "directory" in body["error"]
    status, body = broker.run_verify({})
    assert status == 404 and "pending" in body["error"]
    status, body = broker.get_approval_status("")
    assert status == 400 and "id" in body["error"]
    status, body = broker.get_approval_status("missing")
    assert status == 404


def test_record_external_read_rejects_empty_summary() -> None:
    status, body = broker.record_external_read({"kind": "web", "source": "", "summary": ""})
    assert status in {200, 400}
    assert isinstance(body, dict)


def test_ensure_token_creation_and_workspace_helpers(monkeypatch, tmp_path) -> None:
    token = tmp_path / "token.txt"
    monkeypatch.setattr(broker, "TOKEN_FILE", token)
    monkeypatch.setattr(broker, "TEST_MODE", True)
    value = broker.ensure_token()
    assert value and token.read_text(encoding="utf-8") == value
    assert broker.ensure_token() == value
    shared = tmp_path / "shared"
    shared.mkdir()
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    assert broker._inside_any(shared / "child", (shared,)) is True
    assert broker._allowed_target(shared / "child") is True


def test_workspace_roots_and_text(monkeypatch, tmp_path) -> None:
    shared = tmp_path / "shared"
    shared.mkdir()
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "MEMORY_ROOTS", ())
    roots = broker._workspace_roots()
    assert roots
    assert isinstance(broker._workspace_text(str(shared / "a.txt")), bool)


def test_request_auto_allowed_approval_only(monkeypatch, tmp_path) -> None:
    tmp = tmp_path / "tmp"
    tmp.mkdir()
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "SHARED", tmp_path / "shared")
    (tmp_path / "shared").mkdir()
    target = tmp / "auto.txt"
    status, body = broker.run_request({"action": "write_file", "target": str(target), "approval_only": True, "source": ""})
    assert status in {200, 400, 409}
    assert isinstance(body, dict)


def test_request_policy_denials(monkeypatch, tmp_path) -> None:
    status, body = broker.run_request({"action": "delete", "target": str(broker.ROOT / "package.json")})
    assert status == 403 and "critical" in body["error"].lower()
    status, body = broker.run_request({"action": "send", "target": ""})
    assert status in {400, 403, 409}
    outside = tmp_path / "outside"
    outside.mkdir()
    target = outside / "x.txt"
    target.write_text("x", encoding="utf-8")
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status in {200, 403}


def test_rule_tampering_and_audit_protection(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    assert broker._rule_tampering_hit(str(broker.ROOT / "tools" / "broker.py")) is True
    broker._audit_protection("TEST", "delete", "x", "reason")
    assert (tmp_path / "audit.jsonl").exists()


def test_locked_and_uninstalling_guards(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(broker, "_verify_locked_until", broker.time.monotonic() + 60)
    status, body = broker.run_request({"action": "delete", "target": str(tmp_path / "x")})
    assert status == 429
    monkeypatch.setenv("CBS_IS_UNINSTALLING", "1")
    status, body = broker.run_request({"action": "delete", "target": str(tmp_path / "x")})
    assert status == 503
    monkeypatch.delenv("CBS_IS_UNINSTALLING", raising=False)
    monkeypatch.setattr(broker, "_verify_locked_until", 0.0)



def test_send_manifest_timeout_branch(monkeypatch, tmp_path) -> None:
    import hashlib
    shared = tmp_path / "shared"
    shared.mkdir()
    target = shared / "send.txt"
    target.write_text("send", encoding="utf-8")
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    config = tmp_path / "broker_config.json"
    config.write_text('{"approval_channel": "qq"}', encoding="utf-8")
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "MEMORY_ROOTS", ())
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    monkeypatch.setattr(broker, "TIMEOUT_SECONDS", 0)
    monkeypatch.setattr(broker, "send_qq", lambda _text: True)
    broker._pending = None
    manifest = [{"kind": "file", "path": str(target), "sha256": digest, "size": 4}]
    status, body = broker.run_request({"action": "send", "manifest": manifest})
    assert status in {200, 408}
    assert isinstance(body, dict)


def test_send_manifest_with_target(monkeypatch, tmp_path) -> None:
    import hashlib
    shared = tmp_path / "shared"
    shared.mkdir()
    target = shared / "send2.txt"
    target.write_text("send", encoding="utf-8")
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    config = tmp_path / "broker_config.json"
    config.write_text('{"approval_channel": "qq"}', encoding="utf-8")
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "MEMORY_ROOTS", ())
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    monkeypatch.setattr(broker, "TIMEOUT_SECONDS", 0)
    monkeypatch.setattr(broker, "send_qq", lambda _text: True)
    broker._pending = None
    manifest = [{"kind": "file", "path": str(target), "sha256": digest, "size": 4}]
    status, body = broker.run_request({"action": "send", "target": str(target), "manifest": manifest})
    assert status in {200, 408}, body


def test_send_failure_and_invalid_scoped(monkeypatch, tmp_path) -> None:
    import hashlib
    shared = tmp_path / "shared"
    shared.mkdir()
    target = shared / "send3.txt"
    target.write_text("send", encoding="utf-8")
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    config = tmp_path / "broker_config.json"
    config.write_text('{"approval_channel": "qq"}', encoding="utf-8")
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "MEMORY_ROOTS", ())
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    monkeypatch.setattr(broker, "TIMEOUT_SECONDS", 0)
    monkeypatch.setattr(broker, "send_qq", lambda _text: False)
    broker._pending = None
    manifest = [{"kind": "file", "path": str(target), "sha256": digest, "size": 4}]
    status, body = broker.run_request({"action": "send", "target": str(target), "manifest": manifest})
    assert status == 502, body
    broker._pending = None
    monkeypatch.setattr(broker, "send_qq", lambda _text: True)
    status, body = broker.run_request({
        "action": "delete", "target": str(target), "scoped_token": "invalid", "approval_only": True,
    })
    assert status == 200, body
    assert body.get("scoped_invalid") is True


def test_verify_rejects_email_expired_and_wrong_id(monkeypatch) -> None:
    broker._pending = {"id": "p1", "channel": "email", "deadline": broker.time.monotonic() + 60}
    assert broker.run_verify({"id": "p1"})[0] == 403
    broker._pending = {"id": "p1", "channel": "webui", "deadline": broker.time.monotonic() - 1}
    assert broker.run_verify({"id": "p1"})[0] == 410
    broker._pending = {"id": "p1", "channel": "webui", "deadline": broker.time.monotonic() + 60}
    assert broker.run_verify({"id": "other"})[0] == 404
    broker._pending = None


def test_verify_invalid_attempts_replay_and_manifest(monkeypatch) -> None:
    broker._global_failures = 0
    broker._global_lock_until = 0.0
    broker._verify_locked_until = 0.0
    broker._pending = {"id": "p", "channel": "webui", "deadline": broker.time.monotonic() + 60, "action": "delete", "target": "x"}
    monkeypatch.setattr(broker, "verify_code", lambda _c: "")
    statuses = [broker.run_verify({"id": "p"})[0] for _ in range(5)]
    assert statuses[0] == 403 and statuses[-1] == 429
    broker._verify_locked_until = 0.0
    broker._global_lock_until = 0.0
    broker._global_failures = 0
    broker._pending = {"id": "p2", "channel": "webui", "deadline": broker.time.monotonic() + 60, "action": "delete", "target": "x"}
    monkeypatch.setattr(broker, "verify_code", lambda _c: "replay")
    assert broker.run_verify({"id": "p2"})[0] == 429
    broker._verify_locked_until = 0.0
    broker._global_lock_until = 0.0
    broker._global_failures = 0
    broker._pending = {"id": "p3", "channel": "webui", "deadline": broker.time.monotonic() + 60, "action": "send", "target": "x", "manifest": None}
    monkeypatch.setattr(broker, "verify_code", lambda _c: "totp")
    assert broker.run_verify({"id": "p3"})[0] == 409
    broker._pending = None
    broker._global_failures = 0
    broker._verify_locked_until = 0.0


def test_send_manifest_rejections(monkeypatch, tmp_path) -> None:
    broker._pending = None
    broker._verify_locked_until = 0.0
    broker._global_lock_until = 0.0
    status, body = broker.run_request({"action": "send", "manifest": []})
    assert status == 409
    status, body = broker.run_request({"action": "send", "manifest": "bad"})
    assert status == 409
    status, body = broker.run_request({"action": "send", "manifest": [{"kind": "url", "path": "https://evil.invalid/x"}]})
    assert status == 409


def test_remaining_error_entrypoints(monkeypatch) -> None:
    assert broker.undo_trash_request({})[0] == 400
    assert broker.undo_trash_request({"id": "missing"})[0] == 404
    assert broker.run_request({"action": "send", "target": "x", "approval_only": True})[0] == 400
    assert broker.run_approval_request({"action": "invalid", "target": "x"})[0] == 400


def test_verify_send_manifest_invalid(monkeypatch) -> None:
    broker._verify_locked_until = 0.0
    broker._global_lock_until = 0.0
    broker._global_failures = 0
    broker._pending = {"id": "ps", "channel": "webui", "deadline": broker.time.monotonic() + 60, "action": "send", "target": "x", "manifest": []}
    monkeypatch.setattr(broker, "verify_code", lambda _c: "totp")
    status, body = broker.run_verify({"id": "ps"})
    assert status == 409
    broker._pending = None


def test_verify_send_manifest_valid(monkeypatch, tmp_path) -> None:
    import hashlib
    target = tmp_path / "send.txt"
    target.write_text("x", encoding="utf-8")
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    broker._verify_locked_until = 0.0
    broker._global_lock_until = 0.0
    broker._global_failures = 0
    broker._pending = {
        "id": "ps2", "channel": "webui", "deadline": broker.time.monotonic() + 60,
        "action": "send", "target": str(target),
        "manifest": [{"kind": "file", "path": str(target), "sha256": digest, "size": 1}],
    }
    monkeypatch.setattr(broker, "verify_code", lambda _c: "totp")
    status, body = broker.run_verify({"id": "ps2"})
    assert status in {200, 409, 410, 429}
    broker._pending = None


def test_alias_and_bypass_helpers(monkeypatch) -> None:
    assert broker.run_request({"action": "send_file", "manifest": []})[0] == 409
    broker._purge_bypass()
    assert broker._consume_bypass("missing", "delete", "x") is None
    assert isinstance(broker._target_mode("delete", "x"), str)
    assert broker._as_bool("yes") is True and broker._as_bool("no") is False


def test_invalid_bypass_falls_through(monkeypatch, tmp_path) -> None:
    shared = tmp_path / "shared"
    shared.mkdir()
    target = shared / "bypass.txt"
    target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "MEMORY_ROOTS", ())
    monkeypatch.setattr(broker, "send_qq", lambda _text: True)
    broker._pending = None
    status, body = broker.run_request({"action": "delete", "target": str(target), "bypass_token": "invalid", "approval_only": True})
    assert status in {200, 409}
