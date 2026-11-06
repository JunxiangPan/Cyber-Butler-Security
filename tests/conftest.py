"""Shared test setup for the public release.

The tests intentionally avoid importing AgentRuntime, pywin32, or the live
deployment. They exercise the pure security functions and load the Security
Gate source with minimal AgentRuntime API stubs.
"""

from __future__ import annotations

import os
import sys

import pytest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("CBS_DISABLE_JITTER", "1")
os.environ.setdefault("CBS_DISABLE_ACL", "1")
os.environ.setdefault("CBS_AUDIT_HMAC_KEY", "00" * 32)
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT))


@pytest.fixture(autouse=True)
def _isolate_broker_log(tmp_path, monkeypatch):
    """Keep broker test logging out of the release tree."""
    try:
        import broker
    except Exception:
        return
    monkeypatch.setattr(broker, "LOG", tmp_path / "broker-test.log")
