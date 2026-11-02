"""Detect a listener hijacking the loopback Broker port."""

from __future__ import annotations

import os
import subprocess


class PortHijackError(RuntimeError):
    """Raised when port 18090 is held by an unexpected process."""


def _run(command: list[str]) -> subprocess.CompletedProcess:
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=10,
        creationflags=flags,
    )


def listener_pids(port: int = 18090) -> set[int]:
    if os.name != "nt":
        return set()
    command = [
        "powershell.exe",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        (
            f"$p=@(Get-NetTCPConnection -LocalPort {int(port)} -State Listen "
            "-ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess);"
            "$p | ForEach-Object { [string]$_ }"
        ),
    ]
    result = _run(command)
    pids: set[int] = set()
    for line in (result.stdout or "").splitlines():
        line = line.strip()
        if line.isdigit():
            pids.add(int(line))
    return pids


def assert_broker_port(port: int = 18090, expected_pid: int | None = None) -> None:
    """Fail closed if the port has an owner other than the expected Broker."""
    pids = listener_pids(port)
    if not pids:
        return
    if expected_pid is not None and pids == {int(expected_pid)}:
        return
    raise PortHijackError(
        f"port {port} is already held by PID(s) {sorted(pids)}; refusing to start Broker"
    )
