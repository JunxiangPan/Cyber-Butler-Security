"""Bounded IPC frame codec for the future user-session Helper.

The named-pipe transport, ACL and helper lifecycle are not implemented here.
This module defines the wire frame only so the transport cannot be added later
with an unbounded or ambiguous message format.
"""
from __future__ import annotations

import json
import re
import struct
from dataclasses import asdict, dataclass

MAX_FRAME = 1024 * 1024
VERSION = 1
_HEX64 = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class PipeFrame:
    version: int
    request_id: str
    kind: str
    payload_sha256: str


def encode_frame(frame: PipeFrame) -> bytes:
    if frame.version != VERSION:
        raise ValueError("unsupported IPC version")
    if not frame.request_id:
        raise ValueError("request_id is required")
    if frame.kind not in {"request", "response"}:
        raise ValueError("unsupported frame kind")
    if not _HEX64.fullmatch(frame.payload_sha256):
        raise ValueError("payload_sha256 must be bare 64 lowercase hex")
    body = json.dumps(asdict(frame), separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    if len(body) > MAX_FRAME:
        raise ValueError("frame exceeds 1 MiB")
    return struct.pack(">I", len(body)) + body


def decode_frame(data: bytes) -> PipeFrame:
    if len(data) < 4:
        raise ValueError("truncated IPC frame")
    size = struct.unpack(">I", data[:4])[0]
    if size > MAX_FRAME:
        raise ValueError("frame exceeds 1 MiB")
    if len(data) != size + 4:
        raise ValueError("truncated or trailing IPC bytes")
    try:
        raw = json.loads(data[4:].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("invalid IPC JSON") from exc
    if set(raw) != {"version", "request_id", "kind", "payload_sha256"}:
        raise ValueError("unexpected IPC fields")
    frame = PipeFrame(**raw)
    # Reuse the same validation as encode without accepting extra fields.
    if frame.version != VERSION or not frame.request_id or frame.kind not in {"request", "response"}:
        raise ValueError("invalid IPC frame")
    if not _HEX64.fullmatch(frame.payload_sha256):
        raise ValueError("payload_sha256 must be bare 64 lowercase hex")
    return frame
