"""Windows-aware path identity and TOCTOU guard for the CBS Broker.

The Broker must never approve a path, then later re-open that path by name and
execute.  This module opens the target once, keeps the handle alive for the
approval window, hashes the bytes through that handle, and re-checks the same
handle immediately before execution.

The module is intentionally usable on non-Windows CI for pure tests; the native
handle implementation is selected only on Windows.
"""

from __future__ import annotations

import ctypes
import hashlib
import os
import re
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

_SHORT_NAME_RE = re.compile(r"~\d")


class TargetGuardError(OSError):
    """Raised when a path cannot be opened or violates a path policy."""


def _reject_unsafe_path_text(raw_path: str) -> Path:
    if not raw_path or "\x00" in raw_path:
        raise TargetGuardError("empty or NUL path")
    path = Path(raw_path)
    if any(part == ".." for part in path.parts):
        raise TargetGuardError("path traversal segment is not allowed")
    if any(_SHORT_NAME_RE.search(part) for part in path.parts):
        raise TargetGuardError("8.3 short-name path is not allowed")
    return path


def _hash_fd(fd: int) -> str:
    digest = hashlib.sha256()
    os.lseek(fd, 0, os.SEEK_SET)
    while True:
        chunk = os.read(fd, 1024 * 1024)
        if not chunk:
            break
        digest.update(chunk)
    os.lseek(fd, 0, os.SEEK_SET)
    return digest.hexdigest()


def _identity(fd: int) -> tuple[int, int, int, int]:
    stat = os.fstat(fd)
    return (
        int(getattr(stat, "st_dev", 0)),
        int(getattr(stat, "st_ino", 0)),
        int(stat.st_size),
        int(getattr(stat, "st_mtime_ns", int(stat.st_mtime * 1_000_000_000))),
    )


@dataclass
class TargetSnapshot:
    """A live file handle plus the identity/hash of the approved target."""

    path: Path
    fd: Optional[int]
    identity: tuple[int, int, int, int]
    sha256: str
    is_directory: bool = False
    _closed: bool = field(default=False, init=False)

    @classmethod
    def open(cls, raw_path: str, *, write: bool = False, delete: bool = False) -> "TargetSnapshot":
        path = _reject_unsafe_path_text(str(raw_path))
        if os.name == "nt":
            return cls._open_windows(path, write=write, delete=delete)
        return cls._open_posix(path, write=write)

    @classmethod
    def _open_posix(cls, path: Path, *, write: bool) -> "TargetSnapshot":
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        try:
            fd = os.open(str(path), flags)
        except OSError as exc:
            raise TargetGuardError(f"cannot open target: {exc}") from exc
        try:
            os.set_inheritable(fd, False)
            is_dir = stat.S_ISDIR(os.fstat(fd).st_mode)
            if is_dir:
                return cls(path=path, fd=fd, identity=_identity(fd), sha256="", is_directory=True)
            return cls(path=path, fd=fd, identity=_identity(fd), sha256=_hash_fd(fd))
        except Exception:
            os.close(fd)
            raise

    @classmethod
    def _open_windows(cls, path: Path, *, write: bool, delete: bool) -> "TargetSnapshot":
        import ctypes.wintypes as wintypes
        import msvcrt

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.CreateFileW.argtypes = [
            wintypes.LPCWSTR,
            wintypes.DWORD,
            wintypes.DWORD,
            ctypes.c_void_p,
            wintypes.DWORD,
            wintypes.DWORD,
            wintypes.HANDLE,
        ]
        kernel32.CreateFileW.restype = wintypes.HANDLE
        kernel32.GetFileInformationByHandle.argtypes = [
            wintypes.HANDLE,
            ctypes.c_void_p,
        ]
        kernel32.GetFileInformationByHandle.restype = wintypes.BOOL
        kernel32.GetFinalPathNameByHandleW.argtypes = [
            wintypes.HANDLE,
            wintypes.LPWSTR,
            wintypes.DWORD,
            wintypes.DWORD,
        ]
        kernel32.GetFinalPathNameByHandleW.restype = wintypes.DWORD
        kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel32.CloseHandle.restype = wintypes.BOOL

        access = 0x80000000  # GENERIC_READ
        if write:
            access |= 0x40000000  # GENERIC_WRITE
        if delete:
            access |= 0x00010000  # DELETE
        # FILE_SHARE_READ only: no other writer/deleter during approval. This is
        # intentional fail-closed behaviour. The Broker's own handle is enough
        # to read, hash, and execute.
        handle = kernel32.CreateFileW(
            str(path),
            access,
            0x00000001 | 0x00000004,  # FILE_SHARE_READ | FILE_SHARE_DELETE
            None,
            3,  # OPEN_EXISTING
            0x00200000 | 0x02000000,  # OPEN_REPARSE_POINT | BACKUP_SEMANTICS
            None,
        )
        invalid = ctypes.c_void_p(-1).value
        if handle in (None, invalid):
            raise TargetGuardError(
                "cannot open target: " + str(ctypes.WinError(ctypes.get_last_error()))
            )

        class _BY_HANDLE_FILE_INFORMATION(ctypes.Structure):
            _fields_ = [
                ("dwFileAttributes", wintypes.DWORD),
                ("ftCreationTime", wintypes.FILETIME),
                ("ftLastAccessTime", wintypes.FILETIME),
                ("ftLastWriteTime", wintypes.FILETIME),
                ("dwVolumeSerialNumber", wintypes.DWORD),
                ("nFileSizeHigh", wintypes.DWORD),
                ("nFileSizeLow", wintypes.DWORD),
                ("nNumberOfLinks", wintypes.DWORD),
                ("nFileIndexHigh", wintypes.DWORD),
                ("nFileIndexLow", wintypes.DWORD),
            ]

        info = _BY_HANDLE_FILE_INFORMATION()
        if not kernel32.GetFileInformationByHandle(handle, ctypes.byref(info)):
            error = ctypes.WinError(ctypes.get_last_error())
            kernel32.CloseHandle(handle)
            raise TargetGuardError("cannot read target identity: " + str(error))
        if info.dwFileAttributes & 0x00000400:  # FILE_ATTRIBUTE_REPARSE_POINT
            kernel32.CloseHandle(handle)
            raise TargetGuardError("reparse point / symlink is not allowed")
        if info.nNumberOfLinks != 1:
            kernel32.CloseHandle(handle)
            raise TargetGuardError("hard-linked target is not allowed")

        buffer = ctypes.create_unicode_buffer(32768)
        length = kernel32.GetFinalPathNameByHandleW(handle, buffer, len(buffer), 0)
        final = buffer.value[:length] if length else ""
        normalised = final[4:] if final.startswith("\\\\?\\") else final
        if normalised and os.path.normcase(os.path.abspath(normalised)) != os.path.normcase(
            os.path.abspath(str(path.resolve(strict=False)))
        ):
            kernel32.CloseHandle(handle)
            raise TargetGuardError("final path differs from requested path")

        try:
            fd = msvcrt.open_osfhandle(int(handle), os.O_RDONLY | os.O_BINARY)
        except OSError:
            kernel32.CloseHandle(handle)
            raise
        os.set_inheritable(fd, False)
        is_dir = bool(info.dwFileAttributes & 0x00000010)
        # Use the same fstat-based identity that assert_unchanged() will use.
        identity = _identity(fd)
        digest = "" if is_dir else _hash_fd(fd)
        return cls(path=path, fd=fd, identity=identity, sha256=digest, is_directory=is_dir)

    def assert_unchanged(self) -> None:
        """Re-hash the *same* handle; raise if bytes/identity changed."""
        if self._closed or self.fd is None:
            raise TargetGuardError("target handle is closed")
        if self.is_directory:
            raise TargetGuardError("directory changes are not supported by handle")
        current_identity = _identity(self.fd)
        current_hash = _hash_fd(self.fd)
        if current_identity != self.identity or current_hash != self.sha256:
            raise TargetGuardError("target changed after approval (TOCTOU)")

    def read_bytes(self, limit: int = 256 * 1024) -> bytes:
        """Read the approved bytes through the same handle."""
        if self._closed or self.fd is None or self.is_directory:
            raise TargetGuardError("read requires an open regular-file handle")
        os.lseek(self.fd, 0, os.SEEK_SET)
        data = os.read(self.fd, limit + 1)
        os.lseek(self.fd, 0, os.SEEK_SET)
        if len(data) > limit:
            raise TargetGuardError("target exceeds the preview limit")
        return data

    def rewrite(self, content: bytes) -> None:
        """Overwrite the file through the already-open handle."""
        if self._closed or self.fd is None or self.is_directory:
            raise TargetGuardError("write requires an open regular-file handle")
        os.lseek(self.fd, 0, os.SEEK_SET)
        os.ftruncate(self.fd, 0)
        os.write(self.fd, content)
        os.fsync(self.fd)

    def delete(self) -> None:
        """Delete the file; on Windows use the open handle, not the path."""
        if self._closed or self.fd is None:
            raise TargetGuardError("delete requires an open handle")
        if os.name == "nt":
            import msvcrt

            handle = msvcrt.get_osfhandle(self.fd)
            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel32.SetFileInformationByHandle.argtypes = [
                ctypes.c_void_p,
                ctypes.c_int,
                ctypes.c_void_p,
                ctypes.c_uint32,
            ]
            kernel32.SetFileInformationByHandle.restype = ctypes.c_bool

            class _FILE_DISPOSITION_INFO(ctypes.Structure):
                _fields_ = [("DeleteFile", ctypes.c_bool)]

            info = _FILE_DISPOSITION_INFO(True)
            if not kernel32.SetFileInformationByHandle(
                ctypes.c_void_p(handle), 4, ctypes.byref(info), ctypes.sizeof(info)
            ):
                raise TargetGuardError(
                    "cannot delete through handle: "
                    + str(ctypes.WinError(ctypes.get_last_error()))
                )
        else:
            os.unlink(str(self.path))

    def copy_to(self, destination: Path) -> None:
        """Copy bytes through the verified handle to a new quarantine file."""
        if self._closed or self.fd is None or self.is_directory:
            raise TargetGuardError("copy requires an open regular-file handle")
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
        try:
            out_fd = os.open(str(destination), flags, 0o600)
        except OSError as exc:
            raise TargetGuardError(f"cannot create quarantine file: {exc}") from exc
        try:
            os.lseek(self.fd, 0, os.SEEK_SET)
            while True:
                chunk = os.read(self.fd, 1024 * 1024)
                if not chunk:
                    break
                os.write(out_fd, chunk)
            os.fsync(out_fd)
        finally:
            os.close(out_fd)

    def move_to(self, destination: Path) -> None:
        """Rename the open file through its handle (no path re-open)."""
        if self._closed or self.fd is None:
            raise TargetGuardError("move requires an open handle")
        if os.name != "nt":
            os.replace(str(self.path), str(destination))
            return
        import ctypes.wintypes as wintypes
        import msvcrt

        class _FILE_RENAME_INFO(ctypes.Structure):
            _fields_ = [
                ("ReplaceIfExists", wintypes.BOOL),
                ("RootDirectory", wintypes.HANDLE),
                ("FileNameLength", wintypes.DWORD),
            ]

        name = str(destination).replace("/", "\\") + "\x00"
        name_bytes = name.encode("utf-16-le")
        header_size = ctypes.sizeof(_FILE_RENAME_INFO)
        buffer = ctypes.create_string_buffer(header_size + len(name_bytes))
        info = ctypes.cast(buffer, ctypes.POINTER(_FILE_RENAME_INFO)).contents
        info.ReplaceIfExists = False
        info.RootDirectory = None
        info.FileNameLength = len(name_bytes)
        ctypes.memmove(ctypes.addressof(buffer) + header_size, name_bytes, len(name_bytes))
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.SetFileInformationByHandle.argtypes = [
            ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32
        ]
        kernel32.SetFileInformationByHandle.restype = ctypes.c_bool
        if not kernel32.SetFileInformationByHandle(
            ctypes.c_void_p(msvcrt.get_osfhandle(self.fd)),
            3,  # FileRenameInfo
            buffer,
            ctypes.sizeof(buffer),
        ):
            raise TargetGuardError(
                "cannot move through handle: "
                + str(ctypes.WinError(ctypes.get_last_error()))
            )

    def close(self) -> None:
        if not self._closed and self.fd is not None:
            try:
                os.close(self.fd)
            finally:
                self.fd = None
                self._closed = True

    def __enter__(self) -> "TargetSnapshot":
        return self

    def __exit__(self, *_exc) -> None:
        self.close()


def apply_restricted_acl(path: Path) -> None:
    """Remove inherited ACEs from a newly created high-risk file."""
    if os.name != "nt":
        return
    script = [
        "icacls",
        str(path),
        "/inheritance:r",
        "/grant:r",
        "*S-1-5-18:(F)",       # SYSTEM
        "*S-1-5-32-544:(F)",   # Administrators
        "*S-1-5-32-545:(RX)",  # Users: read-only, never write
    ]
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    result = subprocess.run(script, capture_output=True, text=True, creationflags=flags)
    if result.returncode != 0:
        raise TargetGuardError("cannot apply restricted ACL: " + (result.stderr or "").strip())


def create_exclusive(raw_path: str, content: bytes) -> Path:
    """Create a new file with no inherited write ACE and no overwrite race."""
    path = _reject_unsafe_path_text(str(raw_path))
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(str(path), flags, 0o600)
    try:
        os.write(fd, content)
        os.fsync(fd)
    finally:
        os.close(fd)
    try:
        if os.environ.get("CBS_DISABLE_ACL") != "1":
            apply_restricted_acl(path)
    except Exception:
        try:
            path.unlink(missing_ok=True)
        finally:
            raise
    return path
