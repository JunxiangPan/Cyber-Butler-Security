"""P0-4: store helper branches."""
from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

from tools.broker_store import _canonical_manifest, _manifest_equal, _path_summary


def test_manifest_file_and_url_branches(monkeypatch, tmp_path: Path) -> None:
    file = tmp_path / "a.txt"
    file.write_text("store", encoding="utf-8")
    digest = hashlib.sha256(file.read_bytes()).hexdigest()
    result = _canonical_manifest([{"kind": "file", "path": str(file), "sha256": digest, "size": 5}])
    assert result[0]["path"] == str(file.resolve())
    assert result[0]["sha256"] == digest
    monkeypatch.setenv("CBS_URL_ALLOWED_HOSTS", "api.example.test")
    url = _canonical_manifest([{"kind": "url", "path": "https://api.example.test/v1"}])
    assert url[0]["kind"] == "url" and url[0]["size"] == 0
    assert _manifest_equal(result, result)


def test_manifest_and_path_errors(tmp_path: Path) -> None:
    for value in ([], [{"kind": "file"}], [{"kind": "url", "path": "https://evil.example.test/x"}], [{"kind": "wat", "path": "x"}]):
        with pytest.raises(ValueError):
            _canonical_manifest(value)
    assert "missing" in _path_summary(str(tmp_path / "absent"))
    directory = tmp_path / "dir"
    directory.mkdir()
    (directory / "x.txt").write_text("x", encoding="utf-8")
    assert "directory" in _path_summary(str(directory))
