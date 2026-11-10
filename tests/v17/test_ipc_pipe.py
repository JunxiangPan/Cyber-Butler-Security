"""Windows named-pipe transport tests (pywin32)."""
from __future__ import annotations

import os
import threading
import uuid

import pytest

try:
    import win32pipe  # noqa: F401
except ImportError:  # pragma: no cover - Linux CI
    pytest.skip("pywin32 absent", allow_module_level=True)

from tools.ipc_helper import PipeFrame
from tools.ipc_pipe import PipeClient, PipeServer, PipeTransportError, build_security_attributes

pytestmark = pytest.mark.skipif(os.environ.get("CBS_RUN_IPC_PIPE") != "1", reason="named-pipe transport test requires an interactive Windows host")

HASH = "a" * 64


def _name() -> str:
    return r"\\.\pipe\CyberButler.Helper.v1.test." + uuid.uuid4().hex


def test_normal_request_response() -> None:
    name = _name()
    server = PipeServer(pipe_name=name)
    server.start()
    received = []

    def serve() -> None:
        if server.accept(2):
            frame = server.recv()
            received.append(frame)
            server.send(PipeFrame(1, frame.request_id, "response", HASH))

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    with PipeClient(name, timeout=2) as client:
        client.send(PipeFrame(1, "r1", "request", HASH))
        reply = client.recv()
    thread.join(timeout=3)
    server.close()
    assert received and received[0].request_id == "r1"
    assert reply.kind == "response" and reply.request_id == "r1"


def test_connect_timeout() -> None:
    server = PipeServer(pipe_name=_name())
    server.start()
    try:
        with pytest.raises(PipeTransportError):
            PipeClient(server.pipe_name, timeout=0.2).connect()
    finally:
        server.close()


def test_peer_disconnect_is_clean() -> None:
    server = PipeServer(pipe_name=_name())
    server.start()
    client = PipeClient(server.pipe_name, timeout=2)
    client.connect()
    assert server.accept(2) is True
    client.close()
    with pytest.raises(PipeTransportError):
        server.recv()
    server.close()


def test_acl_has_system_and_current_user() -> None:
    sa = build_security_attributes()
    dacl = sa.SECURITY_DESCRIPTOR.GetSecurityDescriptorDacl()
    assert dacl.GetAceCount() >= 2
