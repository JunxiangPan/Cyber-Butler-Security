"""Shared setup for quality tests: keep broker logs out of the release tree."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

os.environ.setdefault("CBS_TEST_MODE", "1")

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


@pytest.fixture(autouse=True)
def _reset_broker_rate_state():
    """Reset cross-test broker throttling and replay state."""
    try:
        import broker  # noqa: F401
        from broker_state import (  # type: ignore[import]
            _request_buckets,
            _verify_locked_until,
            _global_lock_until,
            _global_failures,
            _last_request_at,
            _used_totp,
        )
    except Exception:
        yield
        return
    import broker as broker_module

    state = broker_module.broker_state
    state._request_buckets.clear()
    state._used_totp.clear()
    state._last_request_at = 0.0
    state._verify_locked_until = 0.0
    state._global_lock_until = 0.0
    state._global_failures = 0
    yield
    state._request_buckets.clear()
    state._used_totp.clear()
    state._last_request_at = 0.0
    state._verify_locked_until = 0.0
    state._global_lock_until = 0.0
    state._global_failures = 0
