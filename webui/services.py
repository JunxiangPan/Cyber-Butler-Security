from __future__ import annotations

import asyncio
import re
import socket
import subprocess

_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

import httpx

from settings import Settings


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


def _read_temperatures(node: dict, path: str, cpu: list[float], gpu: list[float]) -> None:
    """Read temperatures.
    
    Args:
        node: caller-supplied value.
        path: caller-supplied value.
        cpu: caller-supplied value.
        gpu: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    text = str(node.get("Text") or "")
    value = str(node.get("Value") or "")
    current = f"{path}/{text}" if text else path
    low = current.lower()
    if "°c" in value.lower():
        match = re.search(r"(-?\d+(?:\.\d+)?)", value)
        if match:
            number = float(match.group(1))
            if "gpu core" in low and any(key in low for key in ("nvidia", "radeon", "gpu")):
                gpu.append(number)
            elif any(key in low for key in ("ryzen", "intel", "cpu")) and any(
                key in low for key in ("cpu package", "core (tctl", "tdie", "cpu core")
            ):
                cpu.append(number)
    for child in node.get("Children") or []:
        if isinstance(child, dict):
            _read_temperatures(child, current, cpu, gpu)


def _nvidia() -> dict | None:
    """Nvidia.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        output = subprocess.check_output(
            [
                "nvidia-smi",
                "--query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total",
                "--format=csv,noheader,nounits",
            ],
            text=True,
            timeout=5,
            creationflags=_NO_WINDOW,
        ).strip()
    except Exception:
        return None
    if not output:
        return None
    parts = [part.strip() for part in output.splitlines()[0].split(",")]
    if len(parts) < 4:
        return None
    try:
        return {
            "temp": float(parts[0]),
            "load": float(parts[1]),
            "used": float(parts[2]),
            "total": float(parts[3]),
        }
    except ValueError:
        return None


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
                except Exception:
                    pass
                return True
            except Exception:
                return False

        broker = await probe(self.settings.broker_port)
        return {
            "ok": True,
            "services": {"broker": broker},
            "checked_at": int(time.time()),
        }

    async def temperatures(self) -> dict:
        """Temperatures.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        cpu: list[float] = []
        gpu: list[float] = []
        lhm_error = ""
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                response = await client.get(self.settings.lhm_url)
                response.raise_for_status()
                _read_temperatures(response.json(), "", cpu, gpu)
        except Exception as exc:
            lhm_error = str(exc)[:160]
        nvidia = await asyncio.to_thread(_nvidia)
        gpu_temp = max(gpu) if gpu else (nvidia["temp"] if nvidia else None)
        cpu_temp = max(cpu) if cpu else None
        return {
            "ok": cpu_temp is not None or gpu_temp is not None,
            "cpu": cpu_temp,
            "gpu": gpu_temp,
            "gpu_load": nvidia["load"] if nvidia else None,
            "vram_used": nvidia["used"] if nvidia else None,
            "vram_total": nvidia["total"] if nvidia else None,
            "source": "LibreHardwareMonitor + nvidia-smi" if nvidia else "LibreHardwareMonitor",
            "error": lhm_error,
        }

    def logs(self, name: str, lines: int = 80) -> dict:
        """Logs.
        
        Args:
            name: caller-supplied value.
            lines: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        files = {

            "broker": self.settings.project_root / "tools" / "totp_broker.log",
            "dashboard": Path(self.settings.local_app_data) / "CyberButler" / "ui-errors.log",

        }
        path = files.get(name)
        if not path:
            raise ServiceError("unknown log name")
        if not path.exists():
            return {"ok": True, "name": name, "available": False, "lines": []}
        try:
            tail = _tail(path, max(1, min(int(lines), 200)))
        except OSError as exc:
            raise ServiceError(f"cannot read log: {exc}") from exc
        return {
            "ok": True,
            "name": name,
            "available": True,
            "lines": [_redact(line)[:500] for line in tail],
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
                            except OSError:
                                pass
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
