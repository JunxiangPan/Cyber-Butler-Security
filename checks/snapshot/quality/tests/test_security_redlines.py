"""Six architectural red-line tests required by the external audit."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


def test_directory_delete_is_rejected_400(tmp_path: Path) -> None:
    target = tmp_path / "folder"
    target.mkdir()
    status, body = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 400, body
    assert "directory" in str(body.get("error", "")).lower()


def test_verify_rejects_caller_supplied_scope(tmp_path: Path, monkeypatch) -> None:
    target = tmp_path / "file.txt"
    target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "verify_code", lambda _code: "totp")
    monkeypatch.setattr(broker, "_assert_snapshots_current", lambda _request: None)
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    broker._pending = {
        "id": "scope-test",
        "action": "delete",
        "target": str(target),
        "channel": "webui",
        "deadline": 10**18,
        "manifest": None,
        "approval_only": True,
        "_snapshot": None,
        "_source_snapshot": None,
        "scope_root": str(target.parent),
        "target_summary": broker._path_summary(str(target)),
    }
    try:
        status, body = broker.run_verify(
            {"id": "scope-test", "code": "123456", "scoped_minutes": 30}
        )
        assert status == 200, body
        assert "scoped_token" not in body
        assert "scoped_expires_in" not in body
    finally:
        broker._pending = None


def test_critical_integrity_scoped_to_root(tmp_path: Path) -> None:
    assert broker._critical_integrity_hit(str(tmp_path / "package.json")) is False
    assert broker._critical_integrity_hit(str(broker.ROOT / "package.json")) is True


def test_service_child_exit_stops_service() -> None:
    source = (ROOT / "installer" / "service" / "CyberButlerAgentRuntimeService.cs").read_text(
        encoding="utf-8-sig"
    )
    assert "child.Exited += ChildExited" in source
    assert "SERVICE_CHILD_EXIT" in source
    assert "Stop()" in source


def test_pending_endpoints_require_token() -> None:
    source = (ROOT / "tools" / "broker.py").read_text(encoding="utf-8")
    for marker in ('parsed.path == "/pending"', 'parsed.path == "/trash"'):
        start = source.index(marker)
        block = source[start:start + 500]
        assert "if not self._auth()" in block, marker


def test_webui_can_read_broker_token_as_desktop_task() -> None:
    source = (ROOT / "installer" / "Install-CyberButler.ps1").read_text(encoding="utf-8-sig")
    assert "$tokenReaders" in source
    assert "$DesktopAccount" in source
    assert '"${tokenReader}:(R)"' in source or "${tokenReader}:(R)" in source
