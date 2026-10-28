# -*- coding: utf-8 -*-
"""TOTP-gated destructive file action broker bridge (HTTP)."""

from __future__ import annotations

from pathlib import Path

import requests
from astrbot import logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.star import Context, Star, register

TRUSTED_QQ = "YOUR_QQ_ID"
ROOT = Path(__file__).resolve().parents[4]
TOKEN_FILE = ROOT / "tools" / "broker_token.txt"
BROKER_URL = "http://127.0.0.1:18090"
PRIVATE_UMO = "qq_sujinyan:FriendMessage:YOUR_QQ_ID"


@register(
    "astrbot_plugin_totp_broker",
    "local",
    "高危文件操作 TOTP Broker：AI 只能提交删除/覆盖请求，由 SYSTEM broker 验证动态码后执行",
    "1.1.0",
)
class TotpBrokerPlugin(Star):
    def __init__(self, context: Context) -> None:
        super().__init__(context)

    @staticmethod
    def _headers() -> dict:
        token = TOKEN_FILE.read_text(encoding="utf-8").strip() if TOKEN_FILE.exists() else ""
        return {"X-Broker-Token": token, "Content-Type": "application/json"}

    def _post(self, path: str, payload: dict, timeout: float = 15) -> requests.Response:
        return requests.post(
            BROKER_URL + path,
            headers=self._headers(),
            json=payload,
            timeout=timeout,
        )

    @filter.llm_tool(name="request_destructive_file_action")
    async def request_destructive_file_action(
        self,
        event: AstrMessageEvent,
        action: str,
        target: str,
        source: str = "",
        reason: str = "",
    ) -> str:
        """请求删除或覆盖文件；必须经主人 TOTP 动态码确认后由高权限 broker 执行。

        Args:
            action(string): delete 或 overwrite
            target(string): 目标文件完整路径
            source(string): overwrite 时的源文件路径，delete 可留空
            reason(string): 操作原因，方便审计
        """
        if str(event.get_sender_id() or "") != TRUSTED_QQ:
            return "只有主人可以发起高危文件操作。"
        action = (action or "").strip().lower()
        if action not in {"delete", "overwrite"}:
            return "只支持 delete 或 overwrite。"
        if not target:
            return "target 不能为空。"
        try:
            response = self._post("/request", {
                "action": action,
                "target": target,
                "source": source,
                "reason": reason[:300],
            })
            data = response.json()
        except Exception as exc:
            logger.warning("[totp_broker] request failed: %s", exc)
            return f"Broker 不可用：{exc}"
        if not response.ok or not data.get("ok"):
            return f"Broker 拒绝了请求：{data.get('error', response.status_code)}"
        request_id = data.get("id", "")
        logger.info("[totp_broker] request queued: %s %s", action, target)
        return f"已提交 {action} 请求（{request_id}），等待主人输入 6 位动态验证码后执行。"

    @filter.on_llm_request(priority=90)
    async def inject_policy(self, event: AstrMessageEvent, req) -> None:
        umo = str(getattr(event, "unified_msg_origin", "") or "")
        if umo != PRIVATE_UMO:
            return
        prompt = getattr(req, "system_prompt", "") or ""
        policy = (
            "\n[安全规则] 任何删除、覆盖、发送隐私文件、执行 shell/PowerShell 的危险操作，"
            "必须调用 request_destructive_file_action，不要直接调用 astrbot_execute_python 或 shell。"
            "该工具会把请求交给 SYSTEM broker，只有主人用 TOTP 动态码确认后才会执行。"
        )
        if "request_destructive_file_action" not in prompt:
            req.system_prompt = prompt + policy

    @filter.event_message_type(filter.EventMessageType.ALL, priority=1100)
    async def capture_totp(self, event: AstrMessageEvent) -> None:
        if str(event.get_sender_id() or "") != TRUSTED_QQ:
            return
        umo = str(getattr(event, "unified_msg_origin", "") or "")
        if umo != PRIVATE_UMO:
            return
        text = str(event.get_message_str() if hasattr(event, "get_message_str") else getattr(event, "message_str", "") or "").strip()
        if not ((len(text) == 6 and text.isdigit()) or (len(text) == 8 and text.isalnum())):
            return
        try:
            response = self._post("/verify", {"code": text}, timeout=20)
            data = response.json()
        except Exception as exc:
            logger.warning("[totp_broker] verify transport failed: %s", exc)
            return
        if response.status_code == 404:
            # No pending request: allow normal chat to continue.
            return
        if response.ok and data.get("ok"):
            await event.send(event.plain_result("验证码通过，Broker 已执行。"))
        else:
            await event.send(event.plain_result(f"验证码未通过：{data.get('error', '未知错误')}"))
        event.stop_event()
