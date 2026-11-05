from __future__ import annotations

import broker_watchdog


def test_missing_state_is_fail_closed(tmp_path):
    assert broker_watchdog.is_fail_closed(tmp_path) is True


def test_healthy_state_reopens_tools(tmp_path, monkeypatch):
    monkeypatch.setattr(broker_watchdog, "check_health", lambda *a, **k: True)
    record = broker_watchdog.run_once(tmp_path)
    assert record["healthy"] is True
    assert broker_watchdog.is_fail_closed(tmp_path) is False


def test_unhealthy_state_fails_closed(tmp_path, monkeypatch):
    monkeypatch.setattr(broker_watchdog, "check_health", lambda *a, **k: False)
    broker_watchdog.run_once(tmp_path)
    assert broker_watchdog.is_fail_closed(tmp_path) is True
