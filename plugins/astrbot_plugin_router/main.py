"""Router signal endpoint + provider-aware gate skeleton.

Scope: local HTTP signal ingestion, router_state/router_events, state_version,
and a read-only gate that checks the *actual* provider before warning about
local availability. /cloud grants and provider overrides are not implemented.
"""
from __future__ import annotations

import hmac
import json
import os
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import win32crypt
from sqlalchemy import text

from astrbot.api import logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.provider import ProviderType
from astrbot.api.star import Context, Star, register
from astrbot.api.web import error_response, json_response, request
from astrbot.core import db_helper
from astrbot.core.message.message_event_result import MessageChain
from astrbot.core.star.filter.command import CommandFilter

SOURCES = {"cloud_fallback", "game_mode"}
EVENT_TYPES = {"local_unavailable", "local_ready", "game_start", "game_end"}
LOCAL_FALLBACK_TEXT = {
    "zh": "本地模型暂不可用，请稍后重试。",
    "en": "Local model is unavailable. Please try again later.",
}
GENERIC_TEXT = {
    "zh": "服务暂时不可用，请稍后重试。",
    "en": "Service temporarily unavailable. Please try again later.",
}
CONSENT_REQUIRED = {
    "zh": "本地模型不可用。回复 /cloud 授权本次云端，或稍后重试。",
    "en": "Local model unavailable. Reply /cloud to authorize this cloud request, or retry later.",
}
CONSENT_GRANTED = {
    "zh": "已授权本次云端请求。请发送下一条消息。",
    "en": "Cloud authorized for one request. Send your next message.",
}
CONSENT_LEGACY = {
    "zh": "legacy provider 模式已启用，/cloud 暂不可用。",
    "en": "Legacy provider mode is enabled; /cloud is unavailable.",
}
DENIED = {
    "zh": "无权使用该命令。",
    "en": "You are not authorized to use this command.",
}


@register(
    "astrbot_plugin_router",
    "Cyber-Butler",
    "Router signal endpoint and provider-aware gate skeleton",
    "0.1.0",
)
class RouterPlugin(Star):
    def __init__(self, context: Context, config: dict | None = None):
        super().__init__(context, config)
        self.config = config or {}
        self.owner_id = str(self.config.get("owner_id") or "").strip()
        self.local_provider_id = str(
            self.config.get("local_provider_id") or "local_qwen36"
        )
        self.cloud_provider_id = str(
            self.config.get("cloud_provider_id") or "deepseek"
        )
        self.token_path = Path(
            os.getenv("ROUTER_SIGNAL_TOKEN_FILE")
            or self.config.get("token_dpapi_path")
            or r"C:\ProgramData\CyberButler\secrets\router_signal.token.dpapi"
        )
        self.settings_path = Path(__file__).resolve().parents[2] / "router" / "settings.json"
        self._token: str | None = None
        self._schema_ready = False
        self._grants: dict[str, float] = {}
        context.register_web_api(
            "/astrbot_plugin_router/signal",
            self.signal,
            ["POST"],
            "Local-only router state signal",
        )
        self._ensure_files()

    def _ensure_files(self) -> None:
        """Create router settings and outbox directories if absent."""
        try:
            base = Path(__file__).resolve().parents[2]
            router_dir = base / "router"
            router_dir.mkdir(parents=True, exist_ok=True)
            settings = router_dir / "settings.json"
            if not settings.exists():
                settings.write_text(
                    json.dumps(
                        {
                            "legacy_provider_patch": True,
                            "router_signal_mode": "skeleton",
                        },
                        indent=2,
                    )
                    + "\n",
                    encoding="utf-8",
                )
            (base / "router-signals" / "outbox").mkdir(
                parents=True, exist_ok=True
            )
        except Exception as exc:
            logger.warning("[router] ensure files failed: %s", exc)

    def _load_token(self) -> str | None:
        """Load the DPAPI-protected signal token, never a plaintext file."""
        if self._token:
            return self._token
        try:
            raw = self.token_path.read_bytes()
            _, plain = win32crypt.CryptUnprotectData(raw, None, None, None, 0)
            self._token = plain.decode("utf-8").strip()
            return self._token
        except Exception as exc:
            logger.warning("[router] signal token unavailable: %s", exc)
            return None

    async def _ensure_schema(self) -> None:
        """Create router tables lazily before the first signal write."""
        if self._schema_ready:
            return
        async with db_helper.get_db() as session:
            async with session.begin():
                await session.execute(
                    text(
                        "CREATE TABLE IF NOT EXISTS router_state ("
                        "id INTEGER PRIMARY KEY CHECK (id=1), "
                        "state_version INTEGER NOT NULL DEFAULT 0, "
                        "local_mode TEXT NOT NULL DEFAULT 'unknown', "
                        "updated_at TEXT NOT NULL)"
                    )
                )
                await session.execute(
                    text(
                        "CREATE TABLE IF NOT EXISTS router_events ("
                        "event_id TEXT PRIMARY KEY, "
                        "source TEXT NOT NULL, "
                        "event_type TEXT NOT NULL, "
                        "state_version INTEGER NOT NULL, "
                        "applied_at TEXT NOT NULL)"
                    )
                )
                await session.execute(
                    text(
                        "INSERT OR IGNORE INTO router_state "
                        "(id,state_version,local_mode,updated_at) "
                        "VALUES (1,0,'unknown',:ts)"
                    ),
                    {"ts": datetime.now(timezone.utc).isoformat()},
                )
        self._schema_ready = True

    async def _read_state(self) -> dict:
        """Read the current router state."""
        async with db_helper.get_db() as session:
            row = (
                await session.execute(
                    text(
                        "SELECT state_version, local_mode FROM router_state "
                        "WHERE id=1"
                    )
                )
            ).first()
        if not row:
            return {"state_version": 0, "local_mode": "unknown"}
        return {"state_version": int(row[0]), "local_mode": str(row[1])}

    async def signal(self):
        """Accept a local state signal, idempotently by event_id."""
        token = self._load_token()
        if not token:
            return error_response("signal token unavailable", status_code=503)
        provided = request.headers.get("X-Router-Signal-Token", "")
        expected = token
        if not hmac.compare_digest(provided, expected):
            return error_response("unauthorized", status_code=401)
        try:
            payload = await request.json(default={}) or {}
        except Exception:
            return error_response("invalid json", status_code=400)
        source = str(payload.get("source") or "")
        event_type = str(payload.get("event_type") or "")
        event_id = str(payload.get("event_id") or "")
        if source not in SOURCES:
            return error_response("unknown source", status_code=400)
        if event_type not in EVENT_TYPES:
            return error_response("unknown event_type", status_code=400)
        try:
            uuid.UUID(event_id)
        except Exception:
            return error_response("event_id must be uuid", status_code=400)
        if len(json.dumps(payload)) > 4096:
            return error_response("payload too large", status_code=413)

        try:
            await self._ensure_schema()
            ts = datetime.now(timezone.utc).isoformat()
            async with db_helper.get_db() as session:
                async with session.begin():
                    inserted = await session.execute(
                        text(
                            "INSERT OR IGNORE INTO router_events "
                            "(event_id,source,event_type,state_version,applied_at) "
                            "VALUES (:id,:source,:type,0,:ts)"
                        ),
                        {
                            "id": event_id,
                            "source": source,
                            "type": event_type,
                            "ts": ts,
                        },
                    )
                    if inserted.rowcount == 0:
                        return json_response(
                            {
                                "ok": True,
                                "duplicate": True,
                                **await self._read_state(),
                            }
                        )
                    state_row = (
                        await session.execute(
                            text(
                                "SELECT state_version, local_mode FROM router_state "
                                "WHERE id=1"
                            )
                        )
                    ).first()
                    version = int(state_row[0]) + 1
                    local_mode = (
                        "unavailable"
                        if event_type == "local_unavailable"
                        else "ready"
                        if event_type == "local_ready"
                        else str(state_row[1])
                    )
                    await session.execute(
                        text(
                            "UPDATE router_state SET state_version=:v, "
                            "local_mode=:mode, updated_at=:ts WHERE id=1"
                        ),
                        {"v": version, "mode": local_mode, "ts": ts},
                    )
                    await session.execute(
                        text(
                            "UPDATE router_events SET state_version=:v "
                            "WHERE event_id=:id"
                        ),
                        {"v": version, "id": event_id},
                    )
            state = await self._read_state()
            return json_response({"ok": True, "duplicate": False, **state})
        except Exception as exc:
            logger.warning("[router] signal persist failed: %s", exc, exc_info=True)
            return error_response("state store failed", status_code=500)

    def _legacy_enabled(self) -> bool:
        """Read the legacy PATCH switch; default True is the rollback path."""
        try:
            data = json.loads(self.settings_path.read_text(encoding="utf-8"))
            return bool(data.get("legacy_provider_patch", True))
        except Exception:
            return True

    def _grant_valid(self, umo: str) -> bool:
        exp = self._grants.get(umo, 0.0)
        if exp <= time.time():
            self._grants.pop(umo, None)
            return False
        return True

    def _consume_grant(self, umo: str) -> bool:
        if not self._grant_valid(umo):
            return False
        self._grants.pop(umo, None)
        return True

    @filter.command("cloud")
    async def cloud_command(self, event: AstrMessageEvent) -> None:
        """Owner-only one-shot cloud authorization command."""
        if not event.is_private_chat():
            return
        if not self._is_owner(event):
            await event.send(MessageChain().message(DENIED[self._lang(event)]))
            event.stop_event()
            return
        if self._legacy_enabled():
            await event.send(MessageChain().message(CONSENT_LEGACY[self._lang(event)]))
            event.stop_event()
            return
        self._grants[event.unified_msg_origin] = time.time() + 120
        await event.send(MessageChain().message(CONSENT_GRANTED[self._lang(event)]))
        event.stop_event()

    def _is_owner(self, event: AstrMessageEvent) -> bool:
        """Return True only for the configured owner's private chat."""
        return bool(
            event.is_private_chat()
            and self.owner_id
            and str(event.get_sender_id()) == self.owner_id
        )

    def _lang(self, event: AstrMessageEvent) -> str:
        """Return zh/en for the current event locale."""
        locale = str(event.get_extra("locale") or "").lower()
        return "en" if locale.startswith("en") else "zh"

    @staticmethod
    def _is_command_event(event: AstrMessageEvent) -> bool:
        """Return True when a registered command handler is activated.

        AstrBot sets is_at_or_wake_command for private messages as well, so a
        bare is_at_or_wake_command check would skip normal private chat.
        """
        for handler in event.get_extra("activated_handlers") or []:
            if any(
                isinstance(item, CommandFilter)
                for item in getattr(handler, "event_filters", [])
            ):
                return True
        return False

    @filter.event_message_type(filter.EventMessageType.ALL, priority=1000)
    async def gate(self, event: AstrMessageEvent) -> None:
        """Gate: local-first, then one-shot owner cloud consent."""
        try:
            if self._legacy_enabled():
                return
            # Commands must reach their command handler. The raw message still
            # has the wake prefix; message_str was already stripped by
            # WakingCheck (for example "/cloud" -> "cloud").
            raw = getattr(getattr(event, "message_obj", None), "raw_message", "")
            if isinstance(raw, dict):
                raw = raw.get("raw_message") or raw.get("message") or ""
            if isinstance(raw, str) and raw.lstrip().startswith("/"):
                return
            if event.is_at_or_wake_command and self._is_command_event(event):
                return
            state = await self._read_state()
            if not isinstance(state, dict):
                return
            mode = str(state.get("local_mode") or "unknown")
            if mode == "ready":
                self._grants.pop(event.unified_msg_origin, None)
                return
            if mode != "unavailable":
                return
            prov = await self.context.provider_manager.get_using_provider_async(
                ProviderType.CHAT_COMPLETION, event.unified_msg_origin
            )
            actual_id = ""
            if prov is not None:
                actual_id = str(
                    (getattr(prov, "provider_config", {}) or {}).get("id") or ""
                )
            if actual_id and actual_id != self.local_provider_id:
                return
            if self._is_owner(event) and self._consume_grant(
                event.unified_msg_origin
            ):
                event.set_extra("selected_provider", self.cloud_provider_id)
                event.set_extra("router_cloud_provider", self.cloud_provider_id)
                event.set_extra("router_agent_type", "cloud_override")
                return
            if self._is_owner(event):
                await event.send(
                    MessageChain().message(CONSENT_REQUIRED[self._lang(event)])
                )
                event.stop_event()
            elif event.is_private_chat():
                await event.send(
                    MessageChain().message(GENERIC_TEXT[self._lang(event)])
                )
                event.stop_event()
            # Group chats fail silently.
        except Exception as exc:
            # A gate failure must never block normal chat. No stop_event here.
            logger.debug("[router] gate failed open: %s", exc)
