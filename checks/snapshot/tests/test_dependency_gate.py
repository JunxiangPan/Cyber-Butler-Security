"""Dependency gate must validate the hashed lock, not the pip-compile input."""
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "quality" / "dependency_gate.py"
HASH = "a" * 64


def _gate():
    spec = importlib.util.spec_from_file_location("dependency_gate", GATE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _write(path: Path, text: str) -> Path:
    path.write_text(text, encoding="utf-8")
    return path


def test_real_repository_lock_is_hash_pinned() -> None:
    assert _gate().check(
        ROOT / "requirements-runtime.txt",
        ROOT / "requirements-runtime.lock",
    ) == []


def test_backslash_continuation_is_one_pinned_block(tmp_path: Path) -> None:
    source = _write(tmp_path / "requirements.txt", "demo>=1.0\n")
    lock = _write(
        tmp_path / "requirements.lock",
        f"demo==1.0 \\\n    --hash=sha256:{HASH}\n",
    )
    assert _gate().check(source, lock) == []


def test_missing_hash_is_rejected(tmp_path: Path) -> None:
    source = _write(tmp_path / "requirements.txt", "demo>=1.0\n")
    lock = _write(tmp_path / "requirements.lock", "demo==1.0\n")
    problems = _gate().check(source, lock)
    assert any("unpinned" in item for item in problems)


def test_uncovered_top_level_requirement_is_rejected(tmp_path: Path) -> None:
    source = _write(tmp_path / "requirements.txt", "demo>=1.0\nother>=2.0\n")
    lock = _write(
        tmp_path / "requirements.lock",
        f"demo==1.0 \\\n    --hash=sha256:{HASH}\n",
    )
    problems = _gate().check(source, lock)
    assert any("other" in item for item in problems)


def test_missing_lock_is_rejected(tmp_path: Path) -> None:
    source = _write(tmp_path / "requirements.txt", "demo>=1.0\n")
    problems = _gate().check(source, tmp_path / "absent.lock")
    assert any("absent.lock" in item for item in problems)


def test_pipeline_installs_from_the_same_hashed_lock() -> None:
    text = (ROOT / "tools" / "Run-ReleasePipeline.ps1").read_text(encoding="utf-8-sig")
    assert "--require-hashes" in text
    assert "requirements-runtime.lock" in text
