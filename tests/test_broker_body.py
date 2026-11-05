"""Regression tests for partial HTTP body reads in the Broker."""
from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

import broker


class _ChunkedReader:
    def __init__(self, payload: bytes, chunk: int = 2) -> None:
        self.payload = payload
        self.offset = 0
        self.chunk = chunk

    def read(self, size: int) -> bytes:
        if self.offset >= len(self.payload):
            return b""
        take = min(size, self.chunk, len(self.payload) - self.offset)
        result = self.payload[self.offset:self.offset + take]
        self.offset += take
        return result


def _handler(payload: bytes, declared: int | None = None) -> SimpleNamespace:
    length = len(payload) if declared is None else declared
    return SimpleNamespace(
        headers={"Content-Length": str(length)},
        rfile=_ChunkedReader(payload),
    )


def test_body_reassembles_short_socket_reads() -> None:
    payload = b'{"action":"delete","target":"C:/x.txt","reason":"test"}'
    value = broker.Handler._body(_handler(payload))
    assert value["action"] == "delete"


def test_body_rejects_incomplete_reads() -> None:
    payload = b'{"action":"delete"}'
    with pytest.raises(ValueError):
        broker.Handler._body(_handler(payload, declared=len(payload) + 5))




def test_body_accepts_utf8_bom() -> None:
    payload = bytes([0xEF, 0xBB, 0xBF]) + b'{"action":"delete","target":"C:/x.txt"}'
    value = broker.Handler._body(_handler(payload))
    assert value["action"] == "delete"


def test_body_rejects_invalid_utf8() -> None:
    payload = b'{"action":"delete","target":"C:/' + bytes([0xFF]) + b'.txt"}'
    with pytest.raises(ValueError):
        broker.Handler._body(_handler(payload))
