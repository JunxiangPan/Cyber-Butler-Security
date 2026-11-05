from __future__ import annotations

import os

import broker


def test_request_refuses_while_uninstalling(monkeypatch, tmp_path):
    monkeypatch.setenv("CBS_IS_UNINSTALLING", "1")
    status, body = broker.run_request({"action": "write_file", "target": str(tmp_path / "x"), "content": "x"})
    assert status == 503
    assert body["status"] == "uninstalling"
    assert not (tmp_path / "x").exists()


def test_verify_refuses_while_uninstalling(monkeypatch):
    monkeypatch.setenv("CBS_IS_UNINSTALLING", "1")
    status, body = broker.run_verify({"id": "x", "code": "000000"})
    assert status == 503
    assert body["status"] == "uninstalling"
