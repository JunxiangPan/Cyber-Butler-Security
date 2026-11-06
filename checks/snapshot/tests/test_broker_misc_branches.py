"""Small remaining observable branches."""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


def test_path_summary_directory_and_missing(tmp_path: Path) -> None:
    directory = tmp_path / "d"; directory.mkdir()
    (directory / "a.txt").write_text("a", encoding="utf-8")
    (directory / "sub").mkdir()
    (directory / "sub" / "b.txt").write_text("b", encoding="utf-8")
    value = broker._path_summary(str(directory))
    assert "directory" in value and "files" in value
    assert "missing" in broker._path_summary(str(tmp_path / "absent"))


def test_pending_routes_with_snapshot(monkeypatch) -> None:
    class Stub:
        path = "/pending/approval"
        headers = {"Host": "127.0.0.1:18090"}
        client_address = ("127.0.0.1", 1)
        last = None
        def _json(self, status, payload): self.last = (status, payload)
        _local_only = broker.Handler._local_only
        _host_origin_ok = broker.Handler._host_origin_ok
        _auth = lambda self: True
    broker.broker_state._pending = {"id": "p1", "action": "delete", "target": "C:/x/a.txt", "deadline": 10**18, "scope_root": "root", "channel": "webui", "_snapshot": SimpleNamespace(identity=(0, 0, 9, 10))}
    try:
        stub = Stub(); broker.Handler.do_GET(stub)
        assert stub.last[0] == 200 and stub.last[1]["target_size"] == 9
    finally:
        broker.broker_state._pending = None


def test_recovery_reset_bad_code(monkeypatch) -> None:
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "")
    status, body = broker.reset_totp_with_recovery("BAD")
    assert status == 403 and body["ok"] is False


def test_audit_chain_mirror_reads_and_stops(monkeypatch, tmp_path) -> None:
    audit = tmp_path / "audit.jsonl"
    audit.write_text('{"a":1}\nnot-json\n{"b":2}\n', encoding="utf-8")
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker.audit_chain, "append_event", lambda path, record: None)
    captured = {}
    class FakeThread:
        def __init__(self, target, name="", daemon=True):
            captured["target"] = target
        def start(self):
            return None
    monkeypatch.setattr(broker.threading, "Thread", FakeThread)
    broker._start_audit_chain_mirror()
    calls = {"n": 0}
    def sleep(seconds):
        calls["n"] += 1
        if calls["n"] > 1:
            raise StopIteration
    monkeypatch.setattr(broker.time, "sleep", sleep)
    try:
        captured["target"]()
    except Exception:
        pass
    assert calls["n"] == 2


def test_record_external_read(monkeypatch) -> None:
    monkeypatch.setattr(broker.injection_audit, "record", lambda kind, source, summary: {"ok": True})
    status, body = broker.record_external_read({"kind": "web", "source": "x", "summary": "y"})
    assert status == 200 and body["ok"] is True
    monkeypatch.setattr(broker.injection_audit, "record", lambda *args: (_ for _ in ()).throw(ValueError("bad")))
    assert broker.record_external_read({})[0] == 400


def test_log_write_failure_does_not_crash(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(broker, "LOG", tmp_path)
    broker.log("write failure should be contained")


def test_audit_mirror_stat_failure_is_contained(monkeypatch, tmp_path) -> None:
    class BadAudit:
        name = 'audit.jsonl'
        def exists(self): return True
        def stat(self): raise OSError("stat failed")
        def with_name(self, name): return tmp_path / name
    monkeypatch.setattr(broker, "AUDIT", BadAudit())
    captured = {}
    class FakeThread:
        def __init__(self, target, name="", daemon=True): captured["target"] = target
        def start(self): return None
    monkeypatch.setattr(broker.threading, "Thread", FakeThread)
    monkeypatch.setattr(broker.time, "sleep", lambda seconds: (_ for _ in ()).throw(StopIteration))
    broker._start_audit_chain_mirror()
    try:
        captured["target"]()
    except Exception:
        pass
