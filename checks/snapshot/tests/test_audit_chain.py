from __future__ import annotations

import json

import audit_chain


def test_chain_verifies_and_detects_tamper(tmp_path):
    path = tmp_path / "audit.jsonl"
    audit_chain.append_event(path, {"action": "write", "target": "a"})
    audit_chain.append_event(path, {"action": "delete", "target": "b"})
    ok, reason = audit_chain.verify_chain(path)
    assert ok, reason

    lines = path.read_text(encoding="utf-8").splitlines()
    record = json.loads(lines[0])
    record["event"]["target"] = "tampered"
    lines[0] = json.dumps(record, ensure_ascii=False, sort_keys=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    ok, reason = audit_chain.verify_chain(path)
    assert not ok
    assert "hash mismatch" in reason or "previous hash" in reason


def test_anchor_records_head(tmp_path):
    path = tmp_path / "audit.jsonl"
    audit_chain.append_event(path, {"action": "one"})
    anchor_path = tmp_path / "anchor.json"
    record = audit_chain.anchor(path, anchor_path)
    assert record["seq"] == 1
    assert anchor_path.exists()
