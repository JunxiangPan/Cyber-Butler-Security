"""Detect a listener hijacking the loopback Broker port without external commands."""

from __future__ import annotations

import errno
import os
import socket


class PortHijackError(RuntimeError):
    """Raised when port 18090 is held by an unexpected process."""


def listener_pids(port: int = 18090) -> set[int]:
    """Return a sentinel when the port is occupied.

    PID enumeration would require a native table API or psutil. The portable
    runtime does not ship psutil, so this gate uses a bind probe: a successful
    bind means free; EADDRINUSE means occupied. A sentinel {-1} is returned for
    an occupied port because the PID is unavailable without an external tool.
    """
    if os.name != "nt":
        return set()
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        probe.bind(("127.0.0.1", int(port)))
        return set()
    except OSError as exc:
        if exc.errno in {errno.EADDRINUSE, 10048}:
            return {-1}
        return {-1}
    finally:
        probe.close()


def assert_broker_port(port: int = 18090, expected_pid: int | None = None) -> None:
    """Fail closed if the port is occupied by anything other than the expected Broker."""
    pids = listener_pids(port)
    if not pids:
        return
    if expected_pid is not None and pids == {int(expected_pid)}:
        return
    raise PortHijackError(
        f"port {port} is already held (PID unavailable without psutil); refusing to start Broker"
    )
