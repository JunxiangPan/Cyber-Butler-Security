# -*- coding: utf-8 -*-
"""Startup availability fallback: local Ollama missing -> DeepSeek API.

The plugin only changes the current private session's provider. It never
downloads a model and never starts Ollama. The warning is intentionally
written to both AstrBot's log and a local fallback log.
"""

from __future__ import annotations

import asyncio
import json
import time
from pathlib import Path

import requests
from astrbot import logger
from astrbot.api.star import Context, Star, register

ROOT = Path(__file__).resolve().parents[4]
CONFIG = Path(__file__).resolve().parents[3] / "data" / "cmd_config.json"
TOKEN_FILE = ROOT / ".astrbot_token"
LOG_FILE = ROOT / "AstrBot" / "data" / "cloud-fallback.log"
OLLAMA_API = "http://127.0.0.1:11434/api/tags"
PRIVATE_UMO = "qq_sujinyan:FriendMessage:YOUR_QQ_ID"
LOCAL_PROVIDER = "local_qwen36"
LOCAL_SOURCE = "ollama_local_source"
CLOUD_PROVIDER = "deepseek"
STARTUP_GRACE_SECONDS = 120
CHECK_INTERVAL_SECONDS = 10
WARNING = "未检测到本地模型，已自动切换为纯云端模式"
GRACE_WARNING = "Ollama 尚未就绪，进入 120 秒启动宽限期，暂不切换云端"


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
                return
            switched = await asyncio.to_thread(_switch_cloud)
            if switched:
                if not self._warned:
                    self._warned = True
                    _log_warning()
                return
            await asyncio.sleep(10)
