"""Real I/O failure paths in the broker execution layer.

The filesystem is real; only the throwing syscall is replaced with an OSError
or PermissionError. No test fills a disk or changes host permissions.
"""
from __future__ import annotations

import errno
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


class _Snapshot:
    is_directory = False

    def assert_unchanged(self) -> None:
        return None

    def close(self) -> None:
        return None


def _request(target: Path, **extra) -> dict:
    return {"id": "io-test", "action": "delete", "target": str(target), "_snapshot": _Snapshot(), **extra}


def test_capacity_error_maps_to_507(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"
    target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "_allowed_target", lambda path: True)
    monkeypatch.setattr(broker, "QUARANTINE", tmp_path / "staging")
    monkeypatch.setattr(
        broker.quarantine,
        "quarantine_file",
        lambda *args, **kwargs: (_ for _ in ()).throw(broker.quarantine.QuarantineCapacityError("full")),
    )
    result = broker.execute(_request(target))
    assert result.status == 507
    assert result.code == "trash.capacity_exceeded"


def test_disk_full_oserror_is_caught(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"
    target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "_allowed_target", lambda path: True)
    monkeypatch.setattr(broker, "QUARANTINE", tmp_path / "staging")
    monkeypatch.setattr(
        broker.quarantine,
        "quarantine_file",
        lambda *args, **kwargs: (_ for _ in ()).throw(OSError(errno.ENOSPC, "disk full")),
    )
    result = broker.execute(_request(target))
    assert result.status == 500
    assert result.code == "io.operation_failed"


def test_permission_denied_on_move_is_caught(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"
    target.write_text("x", encoding="utf-8")
    monkeypatch.setattr(broker, "_allowed_target", lambda path: True)
    with patch("broker.shutil.move", side_effect=PermissionError("denied")):
        result = broker.execute({"id": "io-test", "action": "delete", "target": str(target), "_snapshot": None})
    assert result.status == 500
    assert result.code == "io.operation_failed"


def test_write_permission_denied_is_caught(monkeypatch, tmp_path: Path) -> None:
    target = tmp_path / "x.txt"
    monkeypatch.setattr(broker, "_allowed_target", lambda path: True)
    with patch("broker.create_exclusive", side_effect=PermissionError("denied")):
        result = broker.execute({
            "id": "io-test", "action": "write_file", "target": str(target),
            "content": "new", "mode": "create", "_snapshot": None,
        })
    assert result.status == 500
    assert result.code == "io.operation_failed"
