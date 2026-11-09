"""P0-4: Job Object lifecycle paths with a fake kernel32."""
from __future__ import annotations

from types import SimpleNamespace

import broker


class _Function:
    argtypes = None
    restype = None

    def __init__(self, value=1):
        self.value = value

    def __call__(self, *_args):
        return self.value


def test_job_object_lifecycle(monkeypatch) -> None:
    kernel = SimpleNamespace(
        CreateJobObjectW=_Function(123),
        SetInformationJobObject=_Function(1),
        AssignProcessToJobObject=_Function(1),
        IsProcessInJob=_Function(1),
        GetCurrentProcess=_Function(1),
        CloseHandle=_Function(1),
    )
    monkeypatch.setattr(broker.os, "name", "nt")
    monkeypatch.setattr(broker.ctypes, "WinDLL", lambda *_a, **_k: kernel)
    monkeypatch.setattr(broker, "_job_handle", None)
    assert broker.initialize_job_object() is True
    assert broker.initialize_job_object() is True
    broker.close_job_object()
    assert broker._job_handle is None



def test_job_object_create_failure(monkeypatch) -> None:
    kernel = SimpleNamespace(
        CreateJobObjectW=_Function(0),
        SetInformationJobObject=_Function(1),
        AssignProcessToJobObject=_Function(1),
        IsProcessInJob=_Function(1),
        GetCurrentProcess=_Function(1),
        CloseHandle=_Function(1),
    )
    monkeypatch.setattr(broker.os, "name", "nt")
    monkeypatch.setattr(broker.ctypes, "WinDLL", lambda *_a, **_k: kernel)
    monkeypatch.setattr(broker, "_job_handle", None)
    try:
        broker.initialize_job_object()
    except SystemExit:
        return
    raise AssertionError("expected fail-closed SystemExit")
