"""IPC frame codec: bounded, strict, and negative cases."""
from __future__ import annotations

import pytest

from tools.ipc_helper import MAX_FRAME, PipeFrame, decode_frame, encode_frame

HASH = "a" * 64


def test_roundtrip() -> None:
    frame = PipeFrame(version=1, request_id="r1", kind="request", payload_sha256=HASH)
    assert decode_frame(encode_frame(frame)) == frame


def test_oversize_truncated_and_bad_fields() -> None:
    with pytest.raises(ValueError):
        encode_frame(PipeFrame(version=1, request_id="r1", kind="request", payload_sha256="sha256:" + HASH))
    with pytest.raises(ValueError):
        encode_frame(PipeFrame(version=2, request_id="r1", kind="request", payload_sha256=HASH))
    assert len(encode_frame(PipeFrame(version=1, request_id="r1", kind="response", payload_sha256=HASH))) > 4
    with pytest.raises(ValueError):
        decode_frame(b"\x00\x00\x00")
    with pytest.raises(ValueError):
        decode_frame(b"\x00\x00\x00\x01x")
    with pytest.raises(ValueError):
        decode_frame(b"\x7f\xff\xff\xff")


def test_max_frame_boundary() -> None:
    assert MAX_FRAME == 1024 * 1024
