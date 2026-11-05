from __future__ import annotations

import asyncio
import logging
import re
import socket

import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

import httpx

from settings import Settings

logger = logging.getLogger(__name__)


class ServiceError(RuntimeError):
    """ServiceError helper/type."""
    pass


def _redact(text: str) -> str:
    """Redact.
    
    Args:
        text: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    text = re.sub(r"(?i)\bBearer\s+\S+", "Bearer [REDACTED]", text)
    text = re.sub(r"sk-[A-Za-z0-9_-]{6,}", "[REDACTED_API_KEY]", text)
    text = re.sub(r"(?i)(api[_-]?key|token|secret)\s*[:=]\s*[^\s,;]+", r"\1=[REDACTED]", text)
    text = re.sub(r'(?<![A-Za-z])[A-Za-z]:[\\/][^\s"\'<>|]*', "[LOCAL_PATH]", text)
    return text


def _tail(path: Path, limit: int) -> list[str]:
    """Tail.
    
    Args:
        path: caller-supplied value.
        limit: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        return [line.rstrip("\n") for line in deque(handle, maxlen=limit)]


class WebServices:
    """WebServices helper/type."""
    def __init__(self, settings: Settings) -> None:
        """Init.
        
        Args:
            settings: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        self.settings = settings

    async def status(self) -> dict:
        """Status.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        async def probe(port: int) -> bool:
            """Probe.
            
            Args:
                port: caller-supplied value.
            
            Returns:
                Function result, or None when no value is returned.
            """
            try:
                reader, writer = await asyncio.wait_for(
                    asyncio.open_connection("127.0.0.1", port), timeout=1.5
                )
                writer.close()
                try:
                    await writer.wait_closed()
                except Exception as exc:
                    logger.warning("writer close failed: %s", exc)
                return True
            except Exception:
                return False

        broker = await probe(self.settings.broker_port)
        return {
            "ok": True,
            "services": {"broker": broker},
            "checked_at": int(time.time()),
        }

    def backups(self) -> dict:
        """Backups.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        root = self.settings.project_root / "backups"
        if not root.exists() or not root.is_dir():
            return {"ok": True, "available": False, "items": []}
        items: list[dict[str, object]] = []
        total = 0
        for child in sorted(root.iterdir(), key=lambda p: p.name.lower(), reverse=True):
            if len(items) >= 50:
                break
            if child.name.startswith(".") or child.is_symlink():
                continue
            try:
                if child.is_dir():
                    size = 0
                    for file in child.rglob("*"):
                        if file.is_file() and not file.is_symlink():
                            try:
                                size += file.stat().st_size
                            except OSError as exc:
                                logger.warning("backup size failed: %s", exc)
                    kind = "directory"
                elif child.is_file():
                    size = child.stat().st_size
                    kind = "file"
                else:
                    continue
            except OSError:
                continue
            total += size
            items.append({
                "name": child.name,
                "kind": kind,
                "size": int(size),
                "mtime": int(child.stat().st_mtime),
            })
        return {"ok": True, "available": True, "items": items, "total": total}

    def _broker_token(self) -> str:
        """Broker token.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        path = self.settings.project_root / "tools" / "broker_token.txt"
        if not path.is_file():
            raise ServiceError("Broker token file is missing")
        return path.read_text(encoding="utf-8").strip()

    async def security_trash(self) -> dict:
        """Security trash.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        try:
            async with httpx.AsyncClient(timeout=4) as client:
                response = await client.get(
                    f"http://127.0.0.1:{self.settings.broker_port}/trash",
                    headers={"X-Broker-Token": self._broker_token()},
                )
                response.raise_for_status()
                data = response.json()
            return {"ok": True, "available": True, "items": data.get("items", [])}
        except Exception:
            return {"ok": True, "available": False, "items": []}

    async def security_trash_undo(self, request_id: str) -> dict:
        """Security trash undo.
        
        Args:
            request_id: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        try:
            async with httpx.AsyncClient(timeout=6) as client:
                response = await client.post(
                    f"http://127.0.0.1:{self.settings.broker_port}/trash/undo",
                    headers={"X-Broker-Token": self._broker_token()},
                    json={"id": request_id},
                )
                response.raise_for_status()
                return {"ok": True, **response.json()}
        except Exception as exc:
            raise ServiceError(f"trash undo failed: {exc}") from exc

    async def security_pending(self) -> dict:
        """Security pending.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        try:
            async with httpx.AsyncClient(timeout=4) as client:
                response = await client.get(
                    f"http://127.0.0.1:{self.settings.broker_port}/pending/approval",
                    headers={"X-Broker-Token": self._broker_token()},
                )
                response.raise_for_status()
                data = response.json()
            return {"ok": True, "available": True, **data}
        except Exception:
            return {"ok": True, "available": False, "pending": False}

    async def security_verify(self, request_id: str, code: str) -> dict:
        """Security verify.
        
        Args:
            request_id: caller-supplied value.
            code: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        try:
            async with httpx.AsyncClient(timeout=8) as client:
                response = await client.post(
                    f"http://127.0.0.1:{self.settings.broker_port}/verify",
                    headers={"X-Broker-Token": self._broker_token()},
                    json={"id": request_id, "code": code},
                )
                data = response.json()
                return {"ok": response.is_success, "status_code": response.status_code, **data}
        except Exception as exc:
            raise ServiceError(f"verification failed: {exc}") from exc

    async def totp_bind(self) -> dict:
        """Totp bind.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        try:
            async with httpx.AsyncClient(timeout=8) as client:
                response = await client.get(
                    f"http://127.0.0.1:{self.settings.broker_port}/totp/bind",
                    headers={"X-Broker-Token": self._broker_token()},
                )
                response.raise_for_status()
                return {"ok": True, **response.json()}
        except Exception as exc:
            raise ServiceError(f"TOTP binding failed: {exc}") from exc

    async def totp_recovery_reset(self, code: str) -> dict:
        """Totp recovery reset.
        
        Args:
            code: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        try:
            async with httpx.AsyncClient(timeout=8) as client:
                response = await client.post(
                    f"http://127.0.0.1:{self.settings.broker_port}/totp/recovery-reset",
                    headers={"X-Broker-Token": self._broker_token()},
                    json={"code": code},
                )
                data = response.json()
                return {"ok": response.is_success, **data}
        except Exception as exc:
            raise ServiceError(f"TOTP recovery reset failed: {exc}") from exc
