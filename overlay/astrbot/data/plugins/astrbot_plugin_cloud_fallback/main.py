# -*- coding: utf-8 -*-
"""Local availability signal for the router plugin.

Legacy mode still patches the current private session's provider directly.
In non-legacy mode this plugin only signals local availability; the router
gate owns the owner's automatic cloud fallback. ``/cloud`` remains an optional
manual override. The plugin never downloads a model and never starts Ollama.
"""

from __future__ import annotations

import asyncio
import json
import time
import uuid
from pathlib import Path

import requests
import win32crypt
from astrbot import logger
from astrbot.api.star import Context, Star, register

ROOT = Path(__file__).resolve().parents[4]
CONFIG = Path(__file__).resolve().parents[3] / "data" / "cmd_config.json"
TOKEN_FILE = ROOT / ".astrbot_token"
LOG_FILE = ROOT / "AstrBot" / "data" / "cloud-fallback.log"
ROUTER_SETTINGS = ROOT / "AstrBot" / "data" / "router" / "settings.json"
ROUTER_TOKEN_FILE = Path(r"C:/ProgramData/CyberButler/secrets/router_signal.token.dpapi")
ROUTER_SIGNAL_URL = (
    "http://127.0.0.1:6185/api/v1/plugins/extensions/"
    "astrbot_plugin_router/signal"
)
OLLAMA_API = "http://127.0.0.1:11434/api/tags"
PRIVATE_UMO = "YOUR_PLATFORM_ID:FriendMessage:YOUR_QQ_ID"
LOCAL_PROVIDER = "local_qwen36"
LOCAL_SOURCE = "ollama_local_source"
CLOUD_PROVIDER = "deepseek"
STARTUP_GRACE_SECONDS = 90
CHECK_INTERVAL_SECONDS = 10
WARNING = "未检测到本地模型，已自动切换为纯云端模式"
GRACE_WARNING = "Ollama 尚未就绪，进入 90 秒启动宽限期，暂不切换云端"


def _local_enabled() -> bool:
    try:
        data = json.loads(CONFIG.read_text(encoding="utf-8-sig"))
        provider = next(
            (p for p in data.get("provider", []) if p.get("id") == LOCAL_PROVIDER),
            None,
        )
        source = next(
            (s for s in data.get("provider_sources", []) if s.get("id") == LOCAL_SOURCE),
            None,
        )
        return bool(provider and provider.get("enable", True)) and bool(
            source and source.get("enable", True)
        )
    except (OSError, ValueError):
        return False


def _ollama_up() -> bool:
    try:
        response = requests.get(OLLAMA_API, timeout=3)
        return response.ok
    except requests.RequestException:
        return False


def _log_warning() -> None:
    logger.warning(WARNING)
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a", encoding="utf-8") as handle:
            handle.write(WARNING + "\n")
    except OSError:
        pass


def _log_grace_warning() -> None:
    logger.warning(GRACE_WARNING)
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a", encoding="utf-8") as handle:
            handle.write(GRACE_WARNING + "\n")
    except OSError:
        pass


def _legacy_enabled() -> bool:
    """Read legacy PATCH switch; default true is the rollback path."""
    try:
        data = json.loads(ROUTER_SETTINGS.read_text(encoding="utf-8"))
        return bool(data.get("legacy_provider_patch", True))
    except Exception:
        return True


def _send_signal(event_type: str) -> bool:
    """Send one state signal; never falls back to a direct provider PATCH."""
    try:
        astrbot_token = TOKEN_FILE.read_text(encoding="utf-8").strip()
        raw = ROUTER_TOKEN_FILE.read_bytes()
        _, plain = win32crypt.CryptUnprotectData(raw, None, None, None, 0)
        router_token = plain.decode("utf-8").strip()
        response = requests.post(
            ROUTER_SIGNAL_URL,
            headers={
                "Authorization": f"Bearer {astrbot_token}",
                "X-Router-Signal-Token": router_token,
            },
            json={
                "source": "cloud_fallback",
                "event_type": event_type,
                "event_id": str(uuid.uuid4()),
            },
            timeout=5,
        )
        if response.ok:
            return True
        logger.error(
            "[cloud_fallback] router signal rejected: %s %s",
            response.status_code,
            response.text[:200],
        )
    except Exception as exc:
        logger.error("[cloud_fallback] router signal failed: %s", exc)
    return False


def _switch_cloud() -> bool:
    try:
        token = TOKEN_FILE.read_text(encoding="utf-8").strip()
        response = requests.patch(
            "http://127.0.0.1:6185/api/v1/sessions/provider",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "umos": [PRIVATE_UMO],
                "provider_id": CLOUD_PROVIDER,
                "provider_type": "chat_completion",
            },
            timeout=15,
        )
        return response.ok and response.json().get("status") == "ok"
    except Exception as exc:
        logger.warning("[cloud_fallback] provider switch failed: %s", exc)
        return False


@register(
    "astrbot_plugin_cloud_fallback",
    "local",
    "本地 Ollama 不可用时自动将闲聊切到 DeepSeek；纯 API 用户也能启动",
    "1.0.0",
)
class CloudFallbackPlugin(Star):
    def __init__(self, context: Context) -> None:
        super().__init__(context)
        self._task: asyncio.Task | None = None
        self._warned = False

    async def initialize(self) -> None:
        self._task = asyncio.create_task(self._watch())

    async def _watch(self) -> None:
        # AstrBot and Ollama are started by separate scheduled tasks after a
        # reboot. Give Ollama a startup grace period so a slow model service is
        # not mistaken for an intentionally API-only deployment.
        await asyncio.sleep(10)
        local_ready = await asyncio.to_thread(_local_enabled)
        if local_ready:
            deadline = time.monotonic() + STARTUP_GRACE_SECONDS
            warned = False
            while time.monotonic() < deadline:
                if await asyncio.to_thread(_ollama_up):
                    logger.info("[cloud_fallback] Ollama ready within startup grace")
                    return
                if not warned:
                    warned = True
                    _log_grace_warning()
                await asyncio.sleep(CHECK_INTERVAL_SECONDS)
            if await asyncio.to_thread(_ollama_up):
                logger.info("[cloud_fallback] Ollama ready at end of startup grace")
                return

        for _ in range(30):
            local_ready = await asyncio.to_thread(_local_enabled)
            ollama_ready = await asyncio.to_thread(_ollama_up)
            if local_ready and ollama_ready:
                await asyncio.to_thread(_send_signal, "local_ready")
                return
            if await asyncio.to_thread(_legacy_enabled):
                switched = await asyncio.to_thread(_switch_cloud)
                if switched:
                    if not self._warned:
                        self._warned = True
                        _log_warning()
                    return
            else:
                # Non-legacy: signal only; the router gate owns the owner's
                # automatic cloud fallback. /cloud is not required here.
                if await asyncio.to_thread(_send_signal, "local_unavailable"):
                    if not self._warned:
                        self._warned = True
                        logger.error(
                            "[cloud_fallback] local unavailable; router signalled; "
                            "automatic owner fallback owned by router"
                        )
                    return
            await asyncio.sleep(10)
