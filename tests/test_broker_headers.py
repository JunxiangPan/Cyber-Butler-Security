"""Broker Host/Origin hardening and pending-response contract."""

from __future__ import annotations

import json

import broker


def _stub(peer: str, headers: dict[str, str]):
    class Stub:
        client_address = (peer, 5555)
        status = None
        payload = None

        def _json(self, status, payload):
            self.status, self.payload = status, payload

        def _host_origin_ok(self):
            return broker.Handler._host_origin_ok(self)

    stub = Stub()
    stub.headers = headers
    return stub


def test_loopback_with_canonical_host_is_allowed():
    stub = _stub("127.0.0.1", {"Host": "127.0.0.1:18090"})
    assert broker.Handler._local_only(stub) is True


def test_forged_host_is_rejected():
    stub = _stub("127.0.0.1", {"Host": "evil.example"})
    assert broker.Handler._local_only(stub) is False
    assert stub.status == 403


def test_forged_origin_is_rejected():
    stub = _stub("127.0.0.1", {"Host": "127.0.0.1:18090", "Origin": "http://evil.example"})
    assert broker.Handler._local_only(stub) is False
    assert stub.status == 403


def test_loopback_origin_is_allowed():
    stub = _stub("127.0.0.1", {"Host": "localhost:18090", "Origin": "http://127.0.0.1:8765"})
    assert broker.Handler._local_only(stub) is True
