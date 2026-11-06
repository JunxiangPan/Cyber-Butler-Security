"""Additional execute-layer branches that are pure business logic."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


class Snap:
    def __init__(self, path: Path, directory: bool = False) -> None:
        self.path = path
        self.is_directory = directory
        self.identity = (0, 0, 1, 2)

    def assert_unchanged(self) -> None:
        return None

    def close(self) -> None:
        return None


def _run(monkeypatch, tmp_path: Path, action: str, target: Path, **extra):
    monkeypatch.setattr(broker, "_allowed_target", lambda path: True)
    monkeypatch.setattr(broker, "QUARANTINE", tmp_path / "quarantine")
    return broker.execute({"id": "more", "action": action, "target": str(target), **extra})


def test_delete_snapshot_manifest_failure_still_succeeds(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"; target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker.quarantine, "quarantine_file", lambda *a, **k: tmp_path / "entry")
    monkeypatch.setattr(broker.quarantine, "_read_manifest", lambda entry: (_ for _ in ()).throw(OSError("bad")))
    result = _run(monkeypatch, tmp_path, "delete", target, _snapshot=Snap(target))
    assert result.ok is True


def test_directory_snapshot_falls_back_to_move(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "dir"; target.mkdir()
    calls = []
    monkeypatch.setattr(broker.shutil, "move", lambda src, dst: calls.append((src, dst)))
    result = _run(monkeypatch, tmp_path, "delete", target, _snapshot=Snap(target, directory=True))
    assert result.ok is True and calls


def test_overwrite_no_snapshot_copies_backup(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(broker, "inside_shared", lambda path: True)
    target = tmp_path / "x.txt"; target.write_text("old", encoding="utf-8")
    source = tmp_path / "new.txt"; source.write_text("new", encoding="utf-8")
    result = _run(monkeypatch, tmp_path, "overwrite", target, source=str(source), _snapshot=None)
    assert result.ok is True and target.read_text(encoding="utf-8") == "new"


def test_write_file_replace_no_snapshot(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"; target.write_text("old", encoding="utf-8")
    result = _run(monkeypatch, tmp_path, "write_file", target, content="new", mode="replace", _snapshot=None)
    assert result.ok is True and target.read_text(encoding="utf-8") == "new"


def test_target_not_allowed_returns_403(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"; target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "_allowed_target", lambda path: False)
    result = broker.execute({"id": "more", "action": "delete", "target": str(target), "_snapshot": None})
    assert result.status == 403
