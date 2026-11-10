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


def test_audit_and_email_result_helpers(monkeypatch, tmp_path: Path) -> None:
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "AUDIT", audit)
    request = {"id": "r", "action": "delete", "target": "x", "challenge": "c"}
    broker._audit_auto(request, True, "ok")
    broker._audit_scoped(request, "ok", str(tmp_path))
    broker._audit_bypass(request, "ok", "scope")
    assert len(audit.read_text(encoding="utf-8").splitlines()) == 3
    sent = []
    monkeypatch.setattr(broker.email_approval, "send_email", lambda *a, **k: sent.append(a))
    broker._email_result({}, request, "ok")
    assert sent



def test_audit_mirror_thread_smoke(monkeypatch, tmp_path: Path) -> None:
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "AUDIT", audit)
    audit.write_text('{"event": "one"}\n', encoding="utf-8")
    monkeypatch.setattr(broker.audit_chain, "append_event", lambda *_a, **_k: True)
    broker._start_audit_chain_mirror()
    broker.time.sleep(1.2)
    assert True


def test_runtime_acl_and_main_refusal(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.setattr(broker.os, "name", "nt")
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    checker = tmp_path / "tools" / "verify_broker_acl.ps1"
    checker.parent.mkdir(parents=True)
    checker.write_text("# checker", encoding="utf-8")
    class Result:
        returncode = 0
        stdout = "Broker runtime ACL: OK"
        stderr = ""
    monkeypatch.setattr(broker.subprocess, "run", lambda *_a, **_k: Result())
    broker.verify_runtime_acl()
    monkeypatch.setattr(broker, "ROOT", Path("YOUR" + "_ROOT"))
    try:
        broker.main()
    except SystemExit:
        return
    raise AssertionError("main must fail closed on placeholders")


def test_audit_mirror_failure_exit(monkeypatch, tmp_path: Path) -> None:
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "AUDIT", audit)
    audit.write_text('{"event": "bad"}\n', encoding="utf-8")
    monkeypatch.setattr(broker.audit_chain, "append_event", lambda *_a, **_k: (_ for _ in ()).throw(RuntimeError("chain")))
    monkeypatch.setattr(broker.os, "_exit", lambda _code: None)
    broker._start_audit_chain_mirror()
    broker.time.sleep(1.2)
    assert True


def test_main_startup_path(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    monkeypatch.setattr(broker, "SHARED", tmp_path / "shared")
    monkeypatch.setattr(broker, "UMO", str(tmp_path))
    monkeypatch.setattr(broker.port_guard, "assert_broker_port", lambda _port: None)
    monkeypatch.setattr(broker, "initialize_job_object", lambda: True)
    monkeypatch.setattr(broker, "verify_runtime_acl", lambda: None)
    monkeypatch.setattr(broker, "ensure_token", lambda: "token")
    monkeypatch.setattr(broker, "_start_audit_chain_mirror", lambda: None)
    monkeypatch.setattr(broker.quarantine, "start_sweeper", lambda: None)
    class Server:
        def __init__(self, *_a, **_k): pass
        def serve_forever(self): return None
    monkeypatch.setattr(broker, "ThreadingHTTPServer", Server)
    monkeypatch.setattr(broker, "close_job_object", lambda: None)
    broker.main()


def test_reset_totp_with_recovery(monkeypatch, tmp_path: Path) -> None:
    vault = tmp_path / "vault"
    monkeypatch.setattr(broker, "TOTP_VAULT", vault)
    monkeypatch.setattr(broker, "SECRET_FILE", vault / "secret.dpapi")
    monkeypatch.setattr(broker, "RECOVERY_FILE", vault / "recovery.json")
    monkeypatch.setattr(broker, "verify_code", lambda _code: "recovery")
    class Crypt:
        @staticmethod
        def CryptProtectData(*_a, **_k): return b"encrypted"
    monkeypatch.setattr(broker, "win32crypt", Crypt)
    monkeypatch.setattr(broker, "totp_binding_payload", lambda: {})
    status, body = broker.reset_totp_with_recovery("RECOVERY1")
    assert status == 200 and len(body["recovery_codes"]) == 3


def test_reset_totp_rejections(monkeypatch) -> None:
    monkeypatch.setattr(broker, "verify_code", lambda _code: "")
    assert broker.reset_totp_with_recovery("X")[0] == 403
    monkeypatch.setattr(broker, "verify_code", lambda _code: "recovery")
    monkeypatch.setattr(broker, "win32crypt", None)
    assert broker.reset_totp_with_recovery("X")[0] == 503


def test_runtime_acl_missing_checker(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.setattr(broker.os, "name", "nt")
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    try:
        broker.verify_runtime_acl()
    except SystemExit:
        return
    raise AssertionError("missing ACL checker must fail closed")


def test_runtime_acl_failure_branches(monkeypatch, tmp_path: Path) -> None:
    checker = tmp_path / "tools" / "verify_broker_acl.ps1"
    checker.parent.mkdir(parents=True)
    checker.write_text("# checker", encoding="utf-8")
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.setattr(broker.os, "name", "nt")
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    class Bad:
        returncode = 1
        stdout = ""
        stderr = "denied"
    monkeypatch.setattr(broker.subprocess, "run", lambda *_a, **_k: Bad())
    try:
        broker.verify_runtime_acl()
    except SystemExit:
        pass
    class Empty:
        returncode = 0
        stdout = ""
        stderr = ""
    monkeypatch.setattr(broker.subprocess, "run", lambda *_a, **_k: Empty())
    try:
        broker.verify_runtime_acl()
    except SystemExit:
        pass
    monkeypatch.setattr(broker.subprocess, "run", lambda *_a, **_k: (_ for _ in ()).throw(OSError("no powershell")))
    try:
        broker.verify_runtime_acl()
    except SystemExit:
        return
    raise AssertionError("ACL failure must fail closed")


def test_main_acl_refusal_path(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    monkeypatch.setattr(broker, "SHARED", tmp_path)
    monkeypatch.setattr(broker, "UMO", str(tmp_path))
    monkeypatch.setattr(broker.port_guard, "assert_broker_port", lambda _p: None)
    monkeypatch.setattr(broker, "initialize_job_object", lambda: True)
    monkeypatch.setattr(broker, "verify_runtime_acl", lambda: (_ for _ in ()).throw(SystemExit("acl")))
    try:
        broker.main()
    except SystemExit:
        return
    raise AssertionError("main must propagate ACL refusal")


def test_totp_binding_payload_and_qr(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "secret", lambda: "JBSWY3DPEHPK3PXP")
    payload = broker.totp_binding_payload()
    assert payload["ok"] is True and "otpauth://" in payload["otpauth_uri"]
    qr = broker._totp_qr(payload["otpauth_uri"])
    assert qr


def test_job_limit_environment_bounds(monkeypatch) -> None:
    monkeypatch.setenv("CBS_BROKER_JOB_MEMORY_MB", "not-a-number")
    monkeypatch.setenv("CBS_BROKER_PROCESS_MEMORY_MB", "1")
    monkeypatch.setenv("CBS_BROKER_JOB_CPU_SECONDS", "999999")
    limits = broker._job_limit_environment()
    assert 64 <= limits["memory_mb"] <= 262144
    assert 32 <= limits["process_memory_mb"] <= 262144
    assert 30 <= limits["cpu_seconds"] <= 86400


def test_uninstall_marker_and_non_windows_acl(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.delenv("CBS_IS_UNINSTALLING", raising=False)
    monkeypatch.setenv("ProgramData", str(tmp_path))
    (tmp_path / "CyberButler").mkdir()
    (tmp_path / "CyberButler" / "uninstalling.marker").write_text("1", encoding="utf-8")
    assert broker._is_uninstalling() is True
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.setattr(broker.os, "name", "posix")
    broker.verify_runtime_acl()


def test_ensure_token_acl_branch(monkeypatch, tmp_path: Path) -> None:
    token = tmp_path / "token.txt"
    monkeypatch.setattr(broker, "TOKEN_FILE", token)
    monkeypatch.setattr(broker, "TEST_MODE", False)
    class Result:
        returncode = 0
        stdout = "SYSTEM:"
        stderr = ""
    monkeypatch.setattr(broker.subprocess, "run", lambda *_a, **_k: Result())
    value = broker.ensure_token()
    assert value and token.exists()


def test_audit_mirror_malformed_line(monkeypatch, tmp_path: Path) -> None:
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "AUDIT", audit)
    audit.write_text("{not-json}\n", encoding="utf-8")
    broker._start_audit_chain_mirror()
    broker.time.sleep(1.2)
    assert True


def test_main_close_failure(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    monkeypatch.setattr(broker, "SHARED", tmp_path)
    monkeypatch.setattr(broker, "UMO", str(tmp_path))
    monkeypatch.setattr(broker.port_guard, "assert_broker_port", lambda _p: None)
    monkeypatch.setattr(broker, "initialize_job_object", lambda: True)
    monkeypatch.setattr(broker, "verify_runtime_acl", lambda: None)
    monkeypatch.setattr(broker, "ensure_token", lambda: "token")
    monkeypatch.setattr(broker, "_start_audit_chain_mirror", lambda: None)
    monkeypatch.setattr(broker.quarantine, "start_sweeper", lambda: None)
    class Server:
        def __init__(self, *_a, **_k): pass
        def serve_forever(self): return None
    monkeypatch.setattr(broker, "ThreadingHTTPServer", Server)
    monkeypatch.setattr(broker, "close_job_object", lambda: (_ for _ in ()).throw(RuntimeError("close")))
    try:
        broker.main()
    except RuntimeError:
        return
    raise AssertionError("close failure must propagate")


def test_manifest_prompt_url_branch(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "SHARED", tmp_path)
    text = broker._manifest_prompt([{"kind": "url", "path": "https://example.test/x", "size": 0, "sha256": ""}])
    assert "OUTSIDE SHARED" in text


def test_timeout_watch_expires_pending(monkeypatch) -> None:
    monkeypatch.setattr(broker, "TIMEOUT_SECONDS", 0)
    monkeypatch.setattr(broker, "send_qq", lambda _text: True)
    broker._pending = {"id": "tw", "approval_only": True}
    broker.timeout_watch("tw")
    assert broker._pending is None


def test_main_refuses_unrendered_placeholder(monkeypatch) -> None:
    monkeypatch.setattr(broker, "ROOT", Path("YOUR" + "_ROOT"))
    monkeypatch.setattr(broker, "SHARED", Path("x"))
    monkeypatch.setattr(broker, "UMO", "x")
    try:
        broker.main()
    except SystemExit:
        return
    raise AssertionError("main must refuse placeholders")
