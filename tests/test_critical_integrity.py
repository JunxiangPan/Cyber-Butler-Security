from __future__ import annotations

from pathlib import Path

import broker


def _prepare(monkeypatch, tmp_path: Path) -> Path:
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "AUDIT", audit)
    broker._pending = None
    return audit


def test_conftest_write_is_hard_denied_and_audited(monkeypatch, tmp_path: Path):
    audit = _prepare(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    status, body = broker.run_request({
        "action": "write_file",
        "target": str(tmp_path / "conftest.py"),
        "content": "x=1",
        "reason": "format",
    })
    assert status == 403
    assert "hard-denied" in body["error"]
    assert "TEST_TAMPERING_ATTEMPT" in audit.read_text(encoding="utf-8")


def test_github_workflow_is_hard_denied(monkeypatch, tmp_path: Path):
    audit = _prepare(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    target = tmp_path / ".github" / "workflows" / "ci.yml"
    status, _ = broker.run_request({"action": "delete", "target": str(target)})
    assert status == 403
    assert "TEST_TAMPERING_ATTEMPT" in audit.read_text(encoding="utf-8")


def test_rule_file_under_cbs_root_is_hard_denied(monkeypatch, tmp_path: Path):
    audit = _prepare(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    target = tmp_path / "webui" / "data" / "network-policy.json"
    target.parent.mkdir(parents=True)
    target.write_text("{}", encoding="utf-8")
    status, _ = broker.run_request({"action": "write_file", "target": str(target), "content": "{}"})
    assert status == 403
    assert "RULE_TAMPERING_ATTEMPT" in audit.read_text(encoding="utf-8")
