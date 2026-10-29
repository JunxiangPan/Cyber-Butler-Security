# -*- coding: utf-8 -*-
"""Dialogue-state-aware anti-repetition guard for AstrBot.

This plugin is deliberately standalone: it does not import the large
``private_companion`` plugin. It keeps per-session state in memory, applies a
small prompt rule, and rewrites only clearly stale or over-long filler replies.
It can run next to any personal-companion plugin.
"""

from __future__ import annotations

import re
import time
from difflib import SequenceMatcher
from typing import Any

from astrbot import logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.provider import ProviderRequest
from astrbot.api.star import Context, Star, register
from astrbot.core.provider.entities import LLMResponse

DEFAULT_SIMILARITY_THRESHOLD = 0.60
DEFAULT_FOLLOWUP_THRESHOLD = 0.42
DEFAULT_FILLER_MAX_CHARS = 80
DEFAULT_MAX_RECENT = 2
DEFAULT_COOLDOWN_SECONDS = 600

_FOLLOWUP_RE = re.compile(
    r"(真的吗|真的假的|然后呢|接着呢|后来呢|为什么|怎么会|那怎么办|"
    r"还有呢|继续|展开|多说|具体|比如|什么意思|怎么说|你确定|是吗|对吧)"
)
_FILLER_RE = re.compile(r"^(嗯+|哦+|噢+|啊+|好+|好吧|行|可以|随便|哈+|呵+|额+|呃+|……|\.\.\.|[?？!！。]+)$")

DST_PROMPT = """
【对话状态感知（DST）与通用反刍禁令】
1. 同一话题连续追问（真的吗/然后呢/为什么/继续/具体一点）：必须顺着回答、补充细节，禁止强行转移话题。
2. 用户明确换话题：立即停止旧话题，不要反复扯旧账。
3. 用户只回“嗯/哦/好/行/？”或纯表情：只回一句很短的回应，禁止长篇大论。
4. 禁止连续 3 轮重复相同核心观点、情绪词或括号动作；发现复读时立即换视角。
5. “追问”优先于“防复读”：用户继续深挖时允许复用旧话题关键词。
"""


def _compact(text: Any) -> str:
    """Remove punctuation and spaces for intent/similarity comparison."""
    return re.sub(r"[\s\r\n\t\"'“”‘’《》【】\[\]（）(){}<>.,，。！？!?；;：:、~～…—_\-]+", "", str(text or ""))


def _text_similarity(left: Any, right: Any) -> float:
    """Return normalized similarity between two short texts."""
    compact_left = _compact(left)
    compact_right = _compact(right)
    if not compact_left or not compact_right:
        return 0.0
    if compact_left == compact_right:
        return 1.0
    shorter, longer = (
        (compact_left, compact_right)
        if len(compact_left) <= len(compact_right)
        else (compact_right, compact_left)
    )
    if len(shorter) >= 12 and shorter in longer:
        return len(shorter) / max(1, len(longer))
    return SequenceMatcher(None, compact_left, compact_right).ratio()


def _strip_filler(text: Any) -> str:
    """Strip common conversational filler around a reply."""
    value = re.sub(r"\s+", "", str(text or ""))
    return re.sub(
        r"^(?:哥|姐|你|我|的|了|啊|呀|呢|吧|哦|嗯|啦|嘛|真的|有点|今天|现在|刚刚|已经|还是|就是)+|"
        r"(?:哥|姐|你|我|的|了|啊|呀|呢|吧|哦|嗯|啦|嘛|真的|有点|今天|现在|刚刚|已经|还是|就是)+$",
        "",
        value,
    )


def _dst_user_intent(current: Any, previous: Any, threshold: float = DEFAULT_FOLLOWUP_THRESHOLD) -> str:
    """Classify a user turn as followup, filler, or new.

    Args:
        current: Current user message.
        previous: Previous user message.
        threshold: Follow-up similarity threshold.

    Returns:
        ``followup``, ``filler``, or ``new``.
    """
    compact = _compact(current)
    if not compact:
        return "filler"
    if _FILLER_RE.match(compact):
        return "filler"
    if _FOLLOWUP_RE.search(compact):
        return "followup"
    if previous and _text_similarity(current, previous) >= threshold:
        return "followup"
    return "new"


def _dst_reply_similarity(reply: Any, recent_replies: list[Any]) -> float:
    """Return the highest similarity against recent bot replies.

    Args:
        reply: Candidate bot reply.
        recent_replies: Recent bot replies, newest first.

    Returns:
        Highest normalized similarity in the range 0.0 to 1.0.
    """
    candidate = str(reply or "").strip()
    if not candidate:
        return 0.0
    best = 0.0
    for item in recent_replies or []:
        if not item:
            continue
        compact_candidate = _strip_filler(candidate)
        compact_item = _strip_filler(str(item))
        ratio = SequenceMatcher(None, compact_candidate, compact_item).ratio()
        best = max(best, _text_similarity(candidate, item), ratio)
    return best


@register(
    "astrbot_plugin_dst_guard",
    "local",
    "对话状态感知防复读：追问继续深入，换话题跳出旧账，敷衍输入强制短回复",
    "1.0.0",
)
class DstGuardPlugin(Star):
    """Standalone DST guard for private/companion replies."""

    def __init__(self, context: Context, config: dict[str, Any] | None = None) -> None:
        super().__init__(context)
        self.config = config or {}
        self.similarity_threshold = float(
            self.config.get("dst_similarity_threshold", DEFAULT_SIMILARITY_THRESHOLD)
        )
        self.followup_threshold = float(
            self.config.get("dst_followup_threshold", DEFAULT_FOLLOWUP_THRESHOLD)
        )
        self.filler_max_chars = int(
            self.config.get("dst_filler_max_chars", DEFAULT_FILLER_MAX_CHARS)
        )
        self.max_recent = max(1, int(self.config.get("dst_max_recent", DEFAULT_MAX_RECENT)))
        self.cooldown_seconds = int(
            self.config.get("dst_cooldown_seconds", DEFAULT_COOLDOWN_SECONDS)
        )
        self._state: dict[str, dict[str, Any]] = {}

    def _state_for(self, umo: str) -> dict[str, Any]:
        state = self._state.setdefault(
            umo,
            {
                "previous_user": "",
                "last_user": "",
                "recent_bots": [],
                "hits": [],
                "cooldown_until": 0.0,
            },
        )
        return state

    @filter.on_llm_request(priority=950)
    async def remember_user_turn(self, event: AstrMessageEvent, req: ProviderRequest) -> None:
        """Store the previous user turn and inject the DST prompt rule."""
        umo = str(getattr(event, "unified_msg_origin", "") or "")
        if not umo:
            return
        state = self._state_for(umo)
        text = str(getattr(event, "message_str", "") or "").strip()
        if text:
            state["previous_user"] = state.get("last_user") or ""
            state["last_user"] = text
        if bool(self.config.get("dst_inject_prompt", True)):
            current = getattr(req, "system_prompt", "") or ""
            if "【对话状态感知（DST）" not in current:
                try:
                    req.system_prompt = current + "\n\n" + DST_PROMPT
                except Exception:
                    pass

    @filter.on_llm_response(priority=200000)
    async def guard_reply(self, event: AstrMessageEvent, resp: LLMResponse) -> None:
        """Apply follow-up/filler/new-topic behavior before the reply is sent."""
        umo = str(getattr(event, "unified_msg_origin", "") or "")
        if not umo:
            return
        state = self._state_for(umo)
        reply = str(getattr(resp, "completion_text", "") or "").strip()
        if not reply:
            return
        current = str(getattr(event, "message_str", "") or state.get("last_user") or "").strip()
        previous = str(state.get("previous_user") or "")
        intent = _dst_user_intent(current, previous, self.followup_threshold)

        if intent == "followup":
            # A follow-up is allowed to reuse the old topic and wording.
            state["recent_bots"] = ([reply] + list(state.get("recent_bots") or []))[: self.max_recent]
            return

        if intent == "filler":
            if len(_compact(reply)) > self.filler_max_chars:
                self._apply_guard("filler", event, resp, state, "哥，我在呢")
            else:
                state["recent_bots"] = ([reply] + list(state.get("recent_bots") or []))[: self.max_recent]
            return

        similarity = _dst_reply_similarity(reply, state.get("recent_bots") or [])
        if similarity >= self.similarity_threshold:
            self._apply_guard("new_topic_repeat", event, resp, state, "(歪头看着哥)")
            return
        state["recent_bots"] = ([reply] + list(state.get("recent_bots") or []))[: self.max_recent]

    def _apply_guard(
        self,
        reason: str,
        event: AstrMessageEvent,
        resp: LLMResponse,
        state: dict[str, Any],
        fallback: str,
    ) -> None:
        """Replace a stale/filler reply and record a DST hit."""
        original = str(getattr(resp, "completion_text", "") or "")
        try:
            resp.completion_text = fallback
            setattr(resp, "dst_guard_applied", reason)
        except Exception:
            return
        try:
            setattr(event, "_private_companion_dst_disable_segmenting", True)
            setattr(event, "_private_companion_dst_rewrite", True)
        except Exception:
            pass
        now = time.time()
        hits = [float(item or 0) for item in (state.get("hits") or []) if now - float(item or 0) <= self.cooldown_seconds]
        hits.append(now)
        state["hits"] = hits[-8:]
        if len(hits) >= 3:
            state["cooldown_until"] = now + self.cooldown_seconds
            try:
                setattr(event, "_private_companion_dst_cooldown_until", state["cooldown_until"])
            except Exception:
                pass
        state["recent_bots"] = ([fallback] + list(state.get("recent_bots") or []))[: self.max_recent]
        umo = str(getattr(event, "unified_msg_origin", "") or "")
        logger.warning(
            "[dst_guard] reason=%s umo=%s before=%s after=%s",
            reason,
            umo_short(umo),
            original[:120],
            fallback,
        )


def umo_short(umo: str) -> str:
    """Return a short safe UMO label for logs.

    Args:
        umo: Unified message origin.

    Returns:
        A shortened label.
    """
    return umo[:80]
