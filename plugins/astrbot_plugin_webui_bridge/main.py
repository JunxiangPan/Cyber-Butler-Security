"""Inbound-only bridge: Web UI text -> fixed owner AstrBot event.

The Web UI must never use AstrBot's outbound /api/v1/im/messages route. This
plugin accepts an authenticated dashboard POST and commits a synthetic inbound
private message for the configured owner. AstrBot then processes it normally
and sends the persona's reply through QQ.
"""

from __future__ import annotations

import time
import uuid
from collections import deque

from astrbot.api import logger
from astrbot.api.message_components import Plain
from astrbot.api.star import Context, Star, register
from astrbot.api.web import error_response, json_response, request
from astrbot.core.platform import AstrBotMessage, MessageMember, MessageType


@register(
    "astrbot_plugin_webui_bridge",
    "Cyber-Butler",
    "Inbound-only Web UI to fixed-owner bridge",
    "1.0.0",
)
class WebuiBridge(Star):
    def __init__(self, context: Context, config: dict | None = None):
        super().__init__(context, config)
        self.config = config or {}
        self._hits: deque[float] = deque()
        context.register_web_api(
            "/astrbot_plugin_webui_bridge/send",
            self.send_inbound,
            ["POST"],
            "Queue one fixed-owner inbound message from the Web UI",
        )

    def _rate_ok(self) -> bool:
        now = time.monotonic()
        while self._hits and now - self._hits[0] > 60:
            self._hits.popleft()
        if len(self._hits) >= 5:
            return False
        self._hits.append(now)
        return True

    async def send_inbound(self):
        config = getattr(self, "config", {}) or {}
        if not bool(config.get("enabled", True)):
            return error_response("bridge disabled", status_code=403)
        owner_id = str(config.get("owner_id") or "").strip()
        platform_id = str(config.get("platform_id") or "").strip()
        if not owner_id or not platform_id:
            return error_response("owner_id/platform_id is not configured", status_code=503)
        if not self._rate_ok():
            return error_response("rate limited", status_code=429)

        payload = await request.json(default={}) or {}
        text = str(payload.get("message") or "").strip()
        if not text:
            return error_response("empty message", status_code=400)
        if len(text) > 500:
            return error_response("message exceeds 500 characters", status_code=400)

        platform = next(
            (
                item
                for item in self.context.platform_manager.platform_insts
                if item.meta().id == platform_id
            ),
            None,
        )
        if platform is None:
            return error_response("configured QQ platform is offline", status_code=503)

        message_id = uuid.uuid4().hex
        bot_self_id = str(getattr(getattr(platform, "bot", None), "self_id", "") or "")
        raw = {
            "post_type": "message",
            "message_type": "private",
            "sub_type": "friend",
            "message_id": message_id,
            "user_id": int(owner_id),
            "self_id": int(bot_self_id) if bot_self_id.isdigit() else bot_self_id,
            "message": [{"type": "text", "data": {"text": text}}],
            "raw_message": text,
            "font": 0,
            "sender": {"user_id": int(owner_id), "nickname": "主人"},
        }
        message = AstrBotMessage()
        message.self_id = bot_self_id
        message.sender = MessageMember(user_id=owner_id, nickname="主人")
        message.type = MessageType.FRIEND_MESSAGE
        message.session_id = owner_id
        message.message_id = message_id
        message.message = [Plain(text)]
        message.message_str = text
        message.raw_message = raw
        message.timestamp = int(time.time())

        event = platform.create_event(message)
        event.is_wake = True
        event.is_at_or_wake_command = True
        event.role = "admin"
        platform.commit_event(event)
        logger.info(
            "[webui_bridge] queued inbound message id=%s length=%s",
            message_id,
            len(text),
        )
        return json_response({"ok": True, "queued": True, "message_id": message_id})
