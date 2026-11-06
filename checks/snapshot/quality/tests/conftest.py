"""Shared setup for quality tests: keep broker logs out of the release tree."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT))


@pytest.fixture(autouse=True)
def _isolate_broker_log(tmp_path, monkeypatch):
    """Redirect the broker log used by quality tests to a temp file."""
    try:
        import broker
    except Exception:
        return
    monkeypatch.setattr(broker, "LOG", tmp_path / "broker-quality.log")
