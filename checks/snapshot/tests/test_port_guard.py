from __future__ import annotations

import pytest

import port_guard


def test_no_listener_is_allowed(monkeypatch):
    monkeypatch.setattr(port_guard, "listener_pids", lambda port: set())
    port_guard.assert_broker_port(18090)


def test_unknown_owner_is_rejected(monkeypatch):
    monkeypatch.setattr(port_guard, "listener_pids", lambda port: {4242})
    with pytest.raises(port_guard.PortHijackError):
        port_guard.assert_broker_port(18090)


def test_expected_owner_is_allowed(monkeypatch):
    monkeypatch.setattr(port_guard, "listener_pids", lambda port: {4242})
    port_guard.assert_broker_port(18090, expected_pid=4242)
