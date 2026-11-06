"""Dependency gate must fail closed without a valid pin/install command."""
from __future__ import annotations

from pathlib import Path

from cbp import dependency_gate
from cbp.config import GateConfig

LOCK = "requests==2.0 " + chr(92) + "\n    --hash=sha256:" + "a" * 64 + "\n"


def _cfg(tmp_path: Path, lock: str, installer: str) -> GateConfig:
    (tmp_path / "lock").write_text(lock, encoding="utf-8")
    (tmp_path / "install.sh").write_text(installer, encoding="utf-8")
    return GateConfig(root=tmp_path, dependency_lock="lock", install_command="install.sh")


def test_unpinned_line_is_rejected(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path, "requests>=2.0\n", "pip install --require-hashes -r lock\n")
    passed, detail = dependency_gate.run(cfg)
    assert passed is False
    assert "unpinned" in detail


def test_requirement_without_equals_is_rejected(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path, "requests\n", "pip install --require-hashes -r lock\n")
    passed, _detail = dependency_gate.run(cfg)
    assert passed is False


def test_hash_in_comment_does_not_enable_installer(tmp_path: Path) -> None:
    cfg = _cfg(
        tmp_path,
        LOCK,
        "# pip install --require-hashes -r lock\npip install -r lock\n",
    )
    passed, detail = dependency_gate.run(cfg)
    assert passed is False
    assert "lacks --require-hashes" in detail


def test_valid_pin_and_effective_installer_passes(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path, LOCK, "pip install --require-hashes -r lock\n")
    passed, detail = dependency_gate.run(cfg)
    assert passed is True
    assert "pinned with hashes" in detail
