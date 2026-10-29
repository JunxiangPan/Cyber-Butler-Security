from __future__ import annotations

import asyncio
import re
import socket
import subprocess
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

import httpx

from settings import Settings


class ServiceError(RuntimeError):
    pass


def _redact(text: str) -> str:
    text = re.sub(r"(?i)\bBearer\s+\S+", "Bearer [REDACTED]", text)
    text = re.sub(r"sk-[A-Za-z0-9_-]{6,}", "[REDACTED_API_KEY]", text)
    text = re.sub(r"(?i)(api[_-]?key|token|secret)\s*[:=]\s*[^\s,;]+", r"\1=[REDACTED]", text)
    text = re.sub(r'(?<![A-Za-z])[A-Za-z]:[\\/][^\s"\'<>|]*', "[LOCAL_PATH]", text)
    return text


def _tail(path: Path, limit: int) -> list[str]:
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        return [line.rstrip("\n") for line in deque(handle, maxlen=limit)]


def _read_temperatures(node: dict, path: str, cpu: list[float], gpu: list[float]) -> None:
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
    try:
        output = subprocess.check_output(
            [
                "nvidia-smi",
                "--query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total",
                "--format=csv,noheader,nounits",
            ],
            text=True,
            timeout=5,
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
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._chat_lock = asyncio.Lock()

    def _token(self) -> str:
        path = self.settings.astrbot_token_file
        if not path or not Path(path).exists():
            raise ServiceError("AstrBot token file is missing")
        return Path(path).read_text(encoding="utf-8").strip()

    async def status(self) -> dict:
        async def probe(port: int) -> bool:
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

        astrbot, broker, snowluma = await asyncio.gather(
            probe(6185), probe(self.settings.broker_port), probe(self.settings.snowluma_port)
        )
        return {
            "ok": True,
            "services": {
                "astrbot": astrbot,
                "broker": broker,
                "snowluma": snowluma,
            },
            "checked_at": int(time.time()),
        }

    async def temperatures(self) -> dict:
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

    async def astrbot_plugins(self) -> dict:
        token = self._token()
        try:
            async with httpx.AsyncClient(timeout=15) as client:
                response = await client.get(
                    self.settings.astrbot_api + "/api/plugin/get",
                    headers={"Authorization": f"Bearer {token}"},
                )
                response.raise_for_status()
                payload = response.json()
        except Exception as exc:
            raise ServiceError(f"AstrBot plugin API failed: {exc}") from exc
        plugins = []
        for item in payload.get("data") or []:
            plugins.append(
                {
                    "name": item.get("name"),
                    "display_name": item.get("display_name") or item.get("name"),
                    "version": item.get("version"),
                    "author": item.get("author"),
                    "activated": item.get("activated"),
                    "reserved": item.get("reserved"),
                }
            )
        plugins.sort(key=lambda item: (not bool(item.get("activated")), str(item.get("name") or "")))
        return {"ok": True, "count": len(plugins), "plugins": plugins}

    def logs(self, name: str, lines: int = 80) -> dict:
        files = {
            "astrbot": self.settings.project_root / "AstrBot" / "data" / "service-astrbot.out.log",
            "broker": self.settings.project_root / "tools" / "totp_broker.log",
            "dashboard": Path(self.settings.local_app_data) / "CyberButler" / "ui-errors.log",
            "snowluma": self.settings.project_root / "SnowLuma" / "logs" / "guardian-restart.log",
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

    async def enqueue_chat(self, text: str) -> dict:
        """Queue an inbound owner event; never send through the bot account."""
        message = str(text or "").strip()
        if not message:
            raise ServiceError("message is empty")
        if len(message) > 500:
            raise ServiceError("message exceeds 500 characters")
        token = self._token()
        url = (
            self.settings.astrbot_api
            + "/api/v1/plugins/extensions/astrbot_plugin_webui_bridge/send"
        )
        async with self._chat_lock:
            try:
                async with httpx.AsyncClient(timeout=20) as client:
                    response = await client.post(
                        url,
                        json={"message": message},
                        headers={"Authorization": f"Bearer {token}"},
                    )
                    response.raise_for_status()
                    payload = response.json()
            except Exception as exc:
                raise ServiceError(f"inbound bridge failed: {exc}") from exc
        if not payload.get("ok"):
            raise ServiceError("inbound bridge rejected the message")
        return {"ok": True, "queued": True, "length": len(message), "at": int(time.time())}

    async def usage(self) -> dict:
        token = self._token()
        try:
            async with httpx.AsyncClient(timeout=15) as client:
                response = await client.get(
                    self.settings.astrbot_api + "/api/stat/provider-tokens",
                    params={"days": 1},
                    headers={"Authorization": f"Bearer {token}"},
                )
                response.raise_for_status()
                data = (response.json() or {}).get("data") or {}
        except Exception as exc:
            raise ServiceError(f"usage stats failed: {exc}") from exc
        providers = []
        cost = 0.0
        unpriced = []
        for item in data.get("today_by_provider") or []:
            provider_id = str(item.get("provider_id") or "")
            tokens = int(item.get("tokens") or 0)
            pricing = (self.settings.token_pricing or {}).get(provider_id) or {}
            rate = pricing.get("blended_per_million")
            if rate is None:
                if "local" in provider_id.lower() or "ollama" in provider_id.lower():
                    rate = 0.0
                else:
                    unpriced.append(provider_id)
                    rate = 0.0
            cost += (tokens / 1_000_000) * float(rate)
            providers.append({"provider": provider_id, "tokens": tokens, "rate": rate})
        return {
            "ok": True,
            "tokens": int(data.get("today_total_tokens") or 0),
            "calls": int(data.get("today_total_calls") or 0),
            "providers": providers,
            "cost": round(cost, 4),
            "currency": "USD",
            "unpriced": unpriced,
            "pricing_configured": not unpriced,
        }

    def backups(self) -> dict:
        root = self.settings.project_root / "backups"
        if not root.exists() or not root.is_dir():
            return {"ok": True, "available": False, "items": []}
        items = []
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

    async def security_pending(self) -> dict:
        try:
            async with httpx.AsyncClient(timeout=4) as client:
                response = await client.get(
                    f"http://127.0.0.1:{self.settings.broker_port}/pending"
                )
                response.raise_for_status()
                data = response.json()
            return {"ok": True, "available": True, **data}
        except Exception:
            return {"ok": True, "available": False, "pending": False}
