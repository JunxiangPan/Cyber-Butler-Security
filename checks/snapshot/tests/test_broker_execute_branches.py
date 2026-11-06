"""Execute-layer success and failure branches with real temporary files."""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


class Snap:
    def __init__(self, path: Path, data: str = "old") -> None:
        self.path = path
        self.is_directory = False
        self.data = data

    def assert_unchanged(self) -> None:
        return None

    def read_bytes(self, limit: int = 0) -> bytes:
        return self.data.encode()

    def rewrite(self, data: bytes) -> None:
        self.path.write_bytes(data)

    def close(self) -> None:
        return None


def _execute(monkeypatch, tmp_path: Path, action: str, target: Path, **extra):
    monkeypatch.setattr(broker, "_allowed_target", lambda path: True)
    monkeypatch.setattr(broker, "QUARANTINE", tmp_path / "quarantine")
    return broker.execute({"id": "exec", "action": action, "target": str(target), **extra})


def test_delete_without_snapshot_moves_file(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"
    target.write_text("x", encoding="utf-8")
    result = _execute(monkeypatch, tmp_path, "delete", target, _snapshot=None)
    assert result.ok is True
    assert not target.exists()


def test_delete_with_snapshot_uses_quarantine(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"
    target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker.quarantine, "quarantine_file", lambda *a, **k: tmp_path / "entry")
    monkeypatch.setattr(broker.quarantine, "_read_manifest", lambda entry: {"expires_at": "now", "expires_epoch": 1})
    result = _execute(monkeypatch, tmp_path, "delete", target, _snapshot=Snap(target), reason="r")
    assert result.ok is True
    assert result.message.startswith("文件已移入")


def test_overwrite_snapshot_and_missing_source(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "inside_shared", lambda path: True)
    target = tmp_path / "x.txt"
    target.write_text("x", encoding="utf-8")
    source = tmp_path / "source.txt"
    source.write_text("new", encoding="utf-8")
    result = _execute(monkeypatch, tmp_path, "overwrite", target, _snapshot=Snap(target), _source_snapshot=Snap(source, "new"))
    assert result.ok is True
    assert target.read_text(encoding="utf-8") == "new"
    result = _execute(monkeypatch, tmp_path, "overwrite", target, _snapshot=None, _source_snapshot=None, source=str(tmp_path / "absent"))
    assert result.status in {409, 403}


def test_write_file_success_and_validation(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"
    result = _execute(monkeypatch, tmp_path, "write_file", target, content="hello", mode="create")
    assert result.ok is True
    result = _execute(monkeypatch, tmp_path, "write_file", target, content=123, mode="create")
    assert result.status == 400
    result = _execute(monkeypatch, tmp_path, "write_file", target, content="x" * (256 * 1024 + 1), mode="create")
    assert result.status == 413
    result = _execute(monkeypatch, tmp_path, "write_file", target, content="x", mode="create")
    assert result.status == 409


def test_unsupported_action(monkeypatch, tmp_path: Path) -> None:
    result = _execute(monkeypatch, tmp_path, "unknown", tmp_path / "x")
    assert result.status == 400
