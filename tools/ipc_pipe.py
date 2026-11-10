"""Windows named-pipe transport for the Cyber-Butler Helper.

Requires pywin32 on Windows. The frame codec is bounded by ipc_helper.MAX_FRAME.
"""
from __future__ import annotations

import json
import os
import threading
import time
from dataclasses import dataclass

from ipc_helper import MAX_FRAME, PipeFrame, decode_frame, encode_frame

DEFAULT_PIPE = r"\\.\pipe\CyberButler.Helper.v1"
CONNECT_TIMEOUT = 5.0


class PipeTransportError(RuntimeError):
    pass


def _load_pywin32():
    try:
        import win32event
        import win32file
        import win32pipe
        import win32security
        import pywintypes
    except ImportError as exc:  # pragma: no cover - non-Windows
        raise PipeTransportError(f"pywin32 named-pipe support unavailable: {exc}") from exc
    return win32event, win32file, win32pipe, win32security, pywintypes


def _current_user_sid(win32security):
    import win32api
    token = win32security.OpenProcessToken(
        win32api.GetCurrentProcess(), win32security.TOKEN_QUERY
    )
    return win32security.GetTokenInformation(token, win32security.TokenUser)[0]


def build_security_attributes(service_account: str | None = None):
    """DACL: SYSTEM + interactive current user + optional service account."""
    _event, _file, _pipe, win32security, pywintypes = _load_pywin32()
    sd = win32security.SECURITY_DESCRIPTOR()
    acl = win32security.ACL()
    system = win32security.ConvertStringSidToSid("S-1-5-18")
    acl.AddAccessAllowedAce(win32security.ACL_REVISION, 0x1F01FF, system)
    acl.AddAccessAllowedAce(win32security.ACL_REVISION, 0x1F01FF, _current_user_sid(win32security))
    if service_account:
        sid, _domain, _type = win32security.LookupAccountName(None, service_account)
        acl.AddAccessAllowedAce(win32security.ACL_REVISION, 0x1F01FF, sid)
    sd.SetSecurityDescriptorDacl(True, acl, False)
    sa = pywintypes.SECURITY_ATTRIBUTES()
    sa.SECURITY_DESCRIPTOR = sd
    return sa


def _read_exact(win32file, handle, size: int) -> bytes:
    chunks = []
    remaining = size
    while remaining:
        _err, chunk = win32file.ReadFile(handle, remaining)
        if not chunk:
            raise PipeTransportError("peer disconnected")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


@dataclass
class PipeServer:
    pipe_name: str = DEFAULT_PIPE
    service_account: str | None = None
    max_frame: int = MAX_FRAME

    def __post_init__(self) -> None:
        self._handle = None
        self._event = None
        self._connected = False

    def start(self) -> None:
        event, file, pipe, _security, pywintypes = _load_pywin32()
        if self._handle is not None:
            raise PipeTransportError("pipe already started")
        sa = build_security_attributes(self.service_account)
        self._handle = pipe.CreateNamedPipe(
            self.pipe_name,
            pipe.PIPE_ACCESS_DUPLEX | file.FILE_FLAG_OVERLAPPED,
            pipe.PIPE_TYPE_MESSAGE | pipe.PIPE_READMODE_MESSAGE | pipe.PIPE_WAIT
            | pipe.PIPE_REJECT_REMOTE_CLIENTS,
            1, self.max_frame, self.max_frame, 0, sa,
        )
        self._event = event.CreateEvent(None, 0, 0, None)
        self._overlapped = pywintypes.OVERLAPPED()
        self._overlapped.hEvent = self._event

    def accept(self, timeout: float = CONNECT_TIMEOUT) -> bool:
        if self._handle is None:
            raise PipeTransportError("pipe not started")
        event, file, pipe, _security, _pywintypes = _load_pywin32()
        try:
            pipe.ConnectNamedPipe(self._handle, self._overlapped)
        except Exception as exc:
            if getattr(exc, "winerror", None) not in {535, 997}:
                raise
        rc = event.WaitForSingleObject(self._event, int(timeout * 1000))
        if rc != event.WAIT_OBJECT_0:
            pipe.DisconnectNamedPipe(self._handle)
            return False
        file.GetOverlappedResult(self._handle, self._overlapped, False)
        self._connected = True
        return True

    def recv(self) -> PipeFrame:
        _event, win32file, _pipe, _security, _pywintypes = _load_pywin32()
        if not self._connected:
            raise PipeTransportError("not connected")
        length = int.from_bytes(_read_exact(win32file, self._handle, 4), "big")
        if length > self.max_frame:
            raise PipeTransportError("frame exceeds 1 MiB")
        return decode_frame(length.to_bytes(4, "big") + _read_exact(win32file, self._handle, length))

    def send(self, frame: PipeFrame) -> None:
        _event, win32file, _pipe, _security, _pywintypes = _load_pywin32()
        win32file.WriteFile(self._handle, encode_frame(frame))

    def close(self) -> None:
        _event, _file, pipe, _security, _pywintypes = _load_pywin32()
        if self._handle is not None:
            if self._connected:
                try:
                    pipe.DisconnectNamedPipe(self._handle)
                except Exception:
                    pass
            self._handle.Close()
            self._handle = None
            self._connected = False

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *_exc):
        self.close()


class PipeClient:
    def __init__(self, pipe_name: str = DEFAULT_PIPE, timeout: float = CONNECT_TIMEOUT) -> None:
        self.pipe_name = pipe_name
        self.timeout = timeout
        self._handle = None

    def connect(self) -> None:
        _event, win32file, pipe, _security, _pywintypes = _load_pywin32()
        ok = pipe.WaitNamedPipe(self.pipe_name, int(self.timeout * 1000))
        if not ok:
            raise PipeTransportError("pipe connect timeout")
        self._handle = win32file.CreateFile(
            self.pipe_name, win32file.GENERIC_READ | win32file.GENERIC_WRITE,
            0, None, win32file.OPEN_EXISTING, 0, None,
        )
        pipe.SetNamedPipeHandleState(
            self._handle, pipe.PIPE_READMODE_MESSAGE, None, None
        )

    def send(self, frame: PipeFrame) -> None:
        _event, win32file, _pipe, _security, _pywintypes = _load_pywin32()
        win32file.WriteFile(self._handle, encode_frame(frame))

    def recv(self) -> PipeFrame:
        _event, win32file, _pipe, _security, _pywintypes = _load_pywin32()
        length = int.from_bytes(_read_exact(win32file, self._handle, 4), "big")
        if length > MAX_FRAME:
            raise PipeTransportError("frame exceeds 1 MiB")
        return decode_frame(length.to_bytes(4, "big") + _read_exact(win32file, self._handle, length))

    def close(self) -> None:
        if self._handle is not None:
            self._handle.Close()
            self._handle = None

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, *_exc):
        self.close()
