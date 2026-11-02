from __future__ import annotations

import time

import broker


def setup_function() -> None:
    with broker._request_rate_lock:
        broker._request_buckets.clear()


def test_request_bucket_refills_at_thirty_seconds() -> None:
    assert broker._allow_request("owner:write", now=1000.0)[0] is True
    assert broker._allow_request("owner:write", now=1000.1)[0] is True
    assert broker._allow_request("owner:write", now=1000.2)[0] is True
    allowed, retry_after = broker._allow_request("owner:write", now=1000.3)
    assert allowed is False
    assert retry_after >= 1
    assert broker._allow_request("owner:write", now=1030.0)[0] is True


def test_deny_jitter_is_bounded(monkeypatch) -> None:
    sleeps: list[float] = []
    monkeypatch.delenv("CBS_DISABLE_JITTER", raising=False)
    monkeypatch.setattr(broker.time, "sleep", lambda seconds: sleeps.append(seconds))
    broker._deny_jitter()
    assert sleeps
    assert broker.DENY_JITTER_MIN <= sleeps[0] <= broker.DENY_JITTER_MAX
