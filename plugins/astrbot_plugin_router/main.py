"""Router signal endpoint + provider-aware gate skeleton.

Scope: local HTTP signal ingestion, router_state/router_events, state_version,
and a read-only gate that checks the *actual* provider before warning about
local availability. /cloud grants and provider overrides are not implemented.
"""
from __future__ import annotations

import asyncio
import hmac
import json
import os
import re
import sqlite3
import subprocess
import time
import uuid
from contextlib import contextmanager
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
from astrbot.core.utils.astrbot_path import get_astrbot_plugin_data_path

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
LOCAL_COOLDOWN_SECONDS = 120
API_COOLDOWN_SECONDS = 60
LOCAL_REPEAT_COOLDOWN_SECONDS = 600
API_REPEAT_COOLDOWN_SECONDS = 300
LOCAL_RECOVERY_PROBES = 2
LOCAL_RECOVERY_GAP_SECONDS = 10
HARD_API_STATUSES = {401, 402, 403}


class CircuitStore:
    """Durable circuit state in the router plugin's own sqlite database."""

    def __init__(self, path: Path, clock=time.time) -> None:
        self.path = Path(path)
        self._clock = clock
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(self.path), timeout=5)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=5000")
        return conn

    @contextmanager
    def _connection(self):
        conn = self._connect()
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    def _ensure_schema(self) -> None:
        with self._connection() as conn:
            version = int(conn.execute("PRAGMA user_version").fetchone()[0])
            if version > 1:
                raise RuntimeError(f"unsupported router.db schema {version}")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS router_circuits (
                    circuit_key TEXT PRIMARY KEY,
                    provider_kind TEXT NOT NULL,
                    provider_id TEXT NOT NULL,
                    state TEXT NOT NULL,
                    open_until REAL NOT NULL DEFAULT 0,
                    consecutive_opens INTEGER NOT NULL DEFAULT 0,
                    hard_failure INTEGER NOT NULL DEFAULT 0,
                    last_failure_class TEXT,
                    last_error TEXT,
                    probe_owner TEXT,
                    probe_started_at REAL,
                    recovery_count INTEGER NOT NULL DEFAULT 0,
                    last_success_at REAL,
                    updated_at REAL NOT NULL
                )
                """
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_router_circuits_state "
                "ON router_circuits(state, open_until)"
            )
            if version < 1:
                conn.execute("PRAGMA user_version=1")

    @staticmethod
    def _key(kind: str, provider_id: str) -> str:
        return f"{kind}:{provider_id}"

    def _row(self, conn: sqlite3.Connection, kind: str, provider_id: str):
        return conn.execute(
            "SELECT * FROM router_circuits WHERE circuit_key=?",
            (self._key(kind, provider_id),),
        ).fetchone()

    def _insert_default(self, conn: sqlite3.Connection, kind: str, provider_id: str):
        now = self._clock()
        conn.execute(
            "INSERT OR IGNORE INTO router_circuits "
            "(circuit_key,provider_kind,provider_id,state,open_until,"
            "consecutive_opens,hard_failure,recovery_count,updated_at) "
            "VALUES (?,?,?,?,0,0,0,0,?)",
            (self._key(kind, provider_id), kind, provider_id, "CLOSED", now),
        )

    def get(self, kind: str, provider_id: str) -> dict:
        with self._connection() as conn:
            self._insert_default(conn, kind, provider_id)
            row = self._row(conn, kind, provider_id)
            now = self._clock()
            if (
                row["state"] == "OPEN"
                and not row["hard_failure"]
                and row["open_until"] > 0
                and row["open_until"] <= now
            ):
                conn.execute(
                    "UPDATE router_circuits SET state='HALF_OPEN', "
                    "probe_owner=NULL, probe_started_at=NULL, updated_at=? "
                    "WHERE circuit_key=?",
                    (now, self._key(kind, provider_id)),
                )
                row = self._row(conn, kind, provider_id)
            result = dict(row)
            result["remaining_seconds"] = max(
                0.0, float(row["open_until"] or 0) - now
            )
            return result

    def failure(
        self,
        kind: str,
        provider_id: str,
        *,
        error: str = "",
        status_code: int | None = None,
    ) -> dict:
        with self._connection() as conn:
            self._insert_default(conn, kind, provider_id)
            row = self._row(conn, kind, provider_id)
            now = self._clock()
            previous_state = str(row["state"])
            consecutive = int(row["consecutive_opens"] or 0) + 1
            hard = 1 if kind == "api" and status_code in HARD_API_STATUSES else 0
            if hard:
                state = "OPEN"
                open_until = 0.0
                failure_class = f"http_{status_code}"
            else:
                state = "OPEN"
                if kind == "local":
                    cooldown = (
                        LOCAL_REPEAT_COOLDOWN_SECONDS
                        if consecutive > 1 or previous_state != "CLOSED"
                        else LOCAL_COOLDOWN_SECONDS
                    )
                else:
                    cooldown = (
                        API_REPEAT_COOLDOWN_SECONDS
                        if consecutive > 1 or previous_state != "CLOSED"
                        else API_COOLDOWN_SECONDS
                    )
                open_until = now + cooldown
                failure_class = (
                    f"http_{status_code}" if status_code else "provider_failure"
                )
            conn.execute(
                "UPDATE router_circuits SET state=?, open_until=?, "
                "consecutive_opens=?, hard_failure=?, last_failure_class=?, "
                "last_error=?, probe_owner=NULL, probe_started_at=NULL, "
                "recovery_count=0, updated_at=? WHERE circuit_key=?",
                (
                    state,
                    open_until,
                    consecutive,
                    hard,
                    failure_class,
                    error[:500],
                    now,
                    self._key(kind, provider_id),
                ),
            )
            logger.warning(
                "[router] circuit %s:%s -> OPEN cooldown=%ss hard=%s error=%s",
                kind,
                provider_id,
                int(max(0.0, open_until - now)) if not hard else "manual",
                bool(hard),
                error[:160],
            )
        return self.get(kind, provider_id)

    def success(self, kind: str, provider_id: str) -> dict:
        recovered = False
        with self._connection() as conn:
            self._insert_default(conn, kind, provider_id)
            row = self._row(conn, kind, provider_id)
            now = self._clock()
            if kind == "local" and row["state"] == "HALF_OPEN":
                recovery = int(row["recovery_count"] or 0) + 1
                last_success = float(row["last_success_at"] or 0)
                if (
                    recovery < LOCAL_RECOVERY_PROBES
                    or now - last_success < LOCAL_RECOVERY_GAP_SECONDS
                ):
                    conn.execute(
                        "UPDATE router_circuits SET recovery_count=?, "
                        "last_success_at=?, probe_owner=NULL, "
                        "probe_started_at=NULL, updated_at=? WHERE circuit_key=?",
                        (
                            recovery,
                            now,
                            now,
                            self._key(kind, provider_id),
                        ),
                    )
                    logger.info(
                        "[router] circuit local:%s recovery probe %s/%s",
                        provider_id,
                        recovery,
                        LOCAL_RECOVERY_PROBES,
                    )
                    recovered = True
            if not recovered:
                conn.execute(
                    "UPDATE router_circuits SET state='CLOSED', open_until=0, "
                    "consecutive_opens=0, hard_failure=0, "
                    "last_failure_class=NULL, last_error=NULL, "
                    "probe_owner=NULL, probe_started_at=NULL, "
                    "recovery_count=0, updated_at=? WHERE circuit_key=?",
                    (now, self._key(kind, provider_id)),
                )
                logger.info(
                    "[router] circuit %s:%s -> CLOSED", kind, provider_id
                )
        return self.get(kind, provider_id)

    def acquire_probe(self, kind: str, provider_id: str, owner: str) -> bool:
        with self._connection() as conn:
            self._insert_default(conn, kind, provider_id)
            now = self._clock()
            cur = conn.execute(
                "UPDATE router_circuits SET probe_owner=?, probe_started_at=?, "
                "updated_at=? WHERE circuit_key=? AND state='HALF_OPEN' "
                "AND (probe_owner IS NULL OR probe_started_at < ?)",
                (
                    owner,
                    now,
                    now,
                    self._key(kind, provider_id),
                    now - 30,
                ),
            )
            return cur.rowcount == 1

    def clear(self, kind: str, provider_id: str) -> dict:
        with self._connection() as conn:
            now = self._clock()
            conn.execute(
                "INSERT OR IGNORE INTO router_circuits "
                "(circuit_key,provider_kind,provider_id,state,open_until,"
                "consecutive_opens,hard_failure,recovery_count,updated_at) "
                "VALUES (?,?,?,'CLOSED',0,0,0,0,?)",
                (self._key(kind, provider_id), kind, provider_id, now),
            )
            conn.execute(
                "UPDATE router_circuits SET state='CLOSED', open_until=0, "
                "consecutive_opens=0, hard_failure=0, last_failure_class=NULL, "
                "last_error=NULL, probe_owner=NULL, probe_started_at=NULL, "
                "recovery_count=0, updated_at=? WHERE circuit_key=?",
                (now, self._key(kind, provider_id)),
            )
        return self.get(kind, provider_id)


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
        self.db_path = (
            Path(get_astrbot_plugin_data_path())
            / "astrbot_plugin_router"
            / "router.db"
        )
        self._token: str | None = None
        self._schema_ready = False
        self._grants: dict[str, float] = {}
        self._grant_meta: dict[str, dict] = {}
        self._probe_cache: dict[str, tuple[float, bool]] = {}
        self._vram_free_mb: int | None = None
        self._vram_last_sample = 0.0
        self._vram_low_streak = 0
        self._vram_high_streak = 0
        self._vram_force_api = False
        self._game_mode_warned_since: float | None = None
        try:
            self.circuit_store = CircuitStore(self.db_path)
        except Exception as exc:
            self.circuit_store = None
            logger.warning("[router] circuit store unavailable: %s", exc)
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
                        "game_mode TEXT NOT NULL DEFAULT 'off', "
                        "game_mode_since REAL NOT NULL DEFAULT 0, "
                        "updated_at TEXT NOT NULL)"
                    )
                )
                columns = {
                    str(row[1])
                    for row in (
                        await session.execute(text("PRAGMA table_info(router_state)"))
                    ).fetchall()
                }
                if "game_mode" not in columns:
                    await session.execute(
                        text(
                            "ALTER TABLE router_state ADD COLUMN "
                            "game_mode TEXT NOT NULL DEFAULT 'off'"
                        )
                    )
                if "game_mode_since" not in columns:
                    await session.execute(
                        text(
                            "ALTER TABLE router_state ADD COLUMN "
                            "game_mode_since REAL NOT NULL DEFAULT 0"
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
                        "SELECT state_version, local_mode, game_mode, "
                        "game_mode_since FROM router_state WHERE id=1"
                    )
                )
            ).first()
        if not row:
            return {
                "state_version": 0,
                "local_mode": "unknown",
                "game_mode": "off",
                "game_mode_since": 0.0,
            }
        return {
            "state_version": int(row[0]),
            "local_mode": str(row[1]),
            "game_mode": str(row[2] or "off"),
            "game_mode_since": float(row[3] or 0.0),
        }

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
                                "SELECT state_version, local_mode, game_mode, "
                                "game_mode_since FROM router_state WHERE id=1"
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
                    game_mode = str(state_row[2] or "off")
                    game_mode_since = float(state_row[3] or 0.0)
                    if event_type == "game_start":
                        game_mode = "on"
                        game_mode_since = time.time()
                    elif event_type == "game_end":
                        game_mode = "off"
                        game_mode_since = 0.0
                    await session.execute(
                        text(
                            "UPDATE router_state SET state_version=:v, "
                            "local_mode=:mode, game_mode=:game_mode, "
                            "game_mode_since=:game_since, updated_at=:ts "
                            "WHERE id=1"
                        ),
                        {
                            "v": version,
                            "mode": local_mode,
                            "game_mode": game_mode,
                            "game_since": game_mode_since,
                            "ts": ts,
                        },
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

    def _circuit(self, kind: str) -> dict:
        store = getattr(self, "circuit_store", None)
        provider_id = (
            self.local_provider_id if kind == "local" else self.cloud_provider_id
        )
        if store is None:
            return {"state": "CLOSED", "hard_failure": 0, "open_until": 0}
        try:
            return store.get(kind, provider_id)
        except Exception as exc:
            logger.warning("[router] circuit read failed: %s", exc)
            return {"state": "CLOSED", "hard_failure": 0, "open_until": 0}

    async def _local_probe(self) -> bool:
        now = time.time()
        cached = self._probe_cache.get("local")
        if cached and now - cached[0] < 30:
            return cached[1]
        ok = False
        try:
            provider = await self.context.provider_manager.get_provider_by_id(
                self.local_provider_id
            )
            api_base = ""
            if provider is not None:
                api_base = str(
                    (getattr(provider, "provider_config", {}) or {}).get(
                        "api_base", ""
                    )
                )
            if not api_base:
                api_base = "http://127.0.0.1:11434"
            api_base = api_base.rstrip("/")
            if api_base.endswith("/v1"):
                api_base = api_base[:-3].rstrip("/")
            url = api_base + "/api/tags"

            def _probe() -> bool:
                import urllib.request

                with urllib.request.urlopen(url, timeout=3) as response:
                    return int(getattr(response, "status", 200)) == 200

            ok = await asyncio.to_thread(_probe)
        except Exception as exc:
            logger.warning("[router] local probe failed: %s", exc)
        self._probe_cache["local"] = (now, ok)
        return ok

    def _vram_allows_local(self) -> bool:
        now = time.time()
        raw_interval = self.config.get("vram_sample_interval_seconds", 15)
        interval = float(15 if raw_interval is None else raw_interval)
        if now - float(getattr(self, "_vram_last_sample", 0) or 0) < interval:
            return not bool(getattr(self, "_vram_force_api", False))
        self._vram_last_sample = now
        free_mb = None
        try:
            result = subprocess.run(
                [
                    "nvidia-smi",
                    "--query-gpu=memory.free",
                    "--format=csv,noheader,nounits",
                ],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            if result.returncode == 0:
                free_mb = int(result.stdout.strip().splitlines()[0])
        except Exception as exc:
            logger.debug("[router] vram sample unavailable: %s", exc)
        if free_mb is None:
            return not bool(getattr(self, "_vram_force_api", False))
        self._vram_free_mb = free_mb
        threshold = int(self.config.get("vram_low_threshold_mb") or 1000)
        required = int(self.config.get("vram_debounce_count") or 3)
        if free_mb < threshold:
            self._vram_low_streak += 1
            self._vram_high_streak = 0
        else:
            self._vram_high_streak += 1
            self._vram_low_streak = 0
        was_forced = bool(getattr(self, "_vram_force_api", False))
        if self._vram_low_streak >= required:
            self._vram_force_api = True
        elif self._vram_high_streak >= required:
            self._vram_force_api = False
        if was_forced != self._vram_force_api:
            logger.warning(
                "[router] vram free=%s threshold=%s low_streak=%s "
                "high_streak=%s action=%s",
                free_mb,
                threshold,
                self._vram_low_streak,
                self._vram_high_streak,
                "switch_api" if self._vram_force_api else "allow_local",
            )
        return not self._vram_force_api

    def _resolve_override(self, event: AstrMessageEvent) -> dict | None:
        api_only = event.get_extra("router_api_only")
        if isinstance(api_only, dict) or api_only is True:
            return {
                "source": "api_only_task",
                "until": "task_end",
                "task_id": (
                    api_only.get("task_id") if isinstance(api_only, dict) else None
                ),
            }
        if self._is_owner(event):
            text = str(getattr(event, "message_str", "") or "")
            for keyword in ("用 API", "用API", "走云端"):
                if keyword in text:
                    try:
                        event.message_str = text.replace(keyword, "", 1).strip()
                    except Exception:
                        pass
                    return {
                        "source": "owner_keyword",
                        "until": "turn_end",
                    }
        if self._grant_valid(event.unified_msg_origin):
            self._consume_grant(event.unified_msg_origin)
            meta = getattr(self, "_grant_meta", {}).pop(
                event.unified_msg_origin, {}
            )
            return {
                "source": "cloud_command",
                "until": meta.get("expires_at", "expired"),
            }
        return None

    async def _on_router_attempt(
        self,
        *,
        provider_id: str,
        status: str,
        error: str = "",
        content_started: bool = False,
    ) -> None:
        if provider_id == self.local_provider_id:
            kind = "local"
        elif provider_id == self.cloud_provider_id:
            kind = "api"
        else:
            return
        store = getattr(self, "circuit_store", None)
        if store is None:
            return
        try:
            if status == "success":
                await asyncio.to_thread(
                    store.success, kind, provider_id
                )
                return
            match = re.search(r"\b(401|402|403|429)\b", error or "")
            status_code = int(match.group(1)) if match else None
            await asyncio.to_thread(
                store.failure,
                kind,
                provider_id,
                error=error,
                status_code=status_code,
            )
        except Exception as exc:
            logger.warning("[router] circuit update failed: %s", exc)

    def _grant_valid(self, umo: str) -> bool:
        exp = self._grants.get(umo, 0.0)
        if exp <= time.time():
            self._grants.pop(umo, None)
            getattr(self, "_grant_meta", {}).pop(umo, None)
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
        expires_at = time.time() + 120
        self._grants[event.unified_msg_origin] = expires_at
        self._grant_meta[event.unified_msg_origin] = {
            "source": "cloud_command",
            "expires_at": datetime.fromtimestamp(
                expires_at, timezone.utc
            ).isoformat(),
        }
        await event.send(MessageChain().message(CONSENT_GRANTED[self._lang(event)]))
        event.stop_event()

    @filter.command("router")
    async def router_command(self, event: AstrMessageEvent) -> None:
        """Owner-only circuit reset command."""
        if not event.is_private_chat() or not self._is_owner(event):
            await event.send(MessageChain().message(DENIED[self._lang(event)]))
            event.stop_event()
            return
        parts = str(getattr(event, "message_str", "") or "").split()
        action = parts[0].lower() if parts else ""
        target = parts[1].lower() if len(parts) > 1 else ""
        if action != "clear" or target not in {"local", "api"}:
            await event.send(
                MessageChain().message(
                    "用法：/router clear local|api"
                    if self._lang(event) == "zh"
                    else "Usage: /router clear local|api"
                )
            )
            event.stop_event()
            return
        store = getattr(self, "circuit_store", None)
        provider_id = (
            self.local_provider_id if target == "local" else self.cloud_provider_id
        )
        if store is None:
            await event.send(MessageChain().message("circuit store unavailable"))
            event.stop_event()
            return
        await asyncio.to_thread(store.clear, target, provider_id)
        logger.warning(
            "[router] owner cleared circuit kind=%s provider=%s",
            target,
            provider_id,
        )
        await event.send(
            MessageChain().message(f"circuit {target} cleared")
        )
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

    def _warn_game_mode_stale(self, since: float) -> None:
        if not since or time.time() - since <= 8 * 3600:
            return
        if getattr(self, "_game_mode_warned_since", None) == since:
            return
        self._game_mode_warned_since = since
        logger.warning(
            "[router] game_mode has been on for %.1f hours; "
            "game mode 可能未正常结束",
            (time.time() - since) / 3600,
        )

    @filter.event_message_type(filter.EventMessageType.ALL, priority=1000)
    async def gate(self, event: AstrMessageEvent) -> None:
        """Apply explicit override, circuit state and local-first routing."""
        try:
            if self._legacy_enabled():
                return
            raw = getattr(getattr(event, "message_obj", None), "raw_message", "")
            if isinstance(raw, dict):
                raw = raw.get("raw_message") or raw.get("message") or ""
            if isinstance(raw, str) and raw.lstrip().startswith("/"):
                return
            if event.is_at_or_wake_command and self._is_command_event(event):
                return

            await self._ensure_schema()
            state = await self._read_state()
            game_mode = str(state.get("game_mode") or "off") == "on"
            if game_mode:
                self._warn_game_mode_stale(
                    float(state.get("game_mode_since") or 0.0)
                )

            override = self._resolve_override(event)
            # Game mode only affects the configured owner's private chat.
            # Other users fall through to normal local-first/owner fallback
            # handling, so game mode cannot spend API budget for everyone.
            if game_mode and not override and self._is_owner(event):
                api_state = str(self._circuit("api").get("state"))
                if api_state == "OPEN":
                    await self._send_route_unavailable(event)
                    return
                if api_state == "HALF_OPEN":
                    store = getattr(self, "circuit_store", None)
                    if store is None or not await asyncio.to_thread(
                        store.acquire_probe,
                        "api",
                        self.cloud_provider_id,
                        event.unified_msg_origin,
                    ):
                        await self._send_route_unavailable(event)
                        return
                event.set_extra("selected_provider", self.cloud_provider_id)
                event.set_extra("router_cloud_provider", self.cloud_provider_id)
                event.set_extra("router_allow_fallback", False)
                event.set_extra("router_agent_type", "main")
                event.set_extra("router_attempt_callback", self._on_router_attempt)
                event.set_extra("router_override_source", "game_mode")
                event.set_extra("router_override_until", "game_end")
                logger.info(
                    "[router] route=cloud reason=game_mode override=game_mode "
                    "until=game_end api_state=%s",
                    api_state,
                )
                return
            local_circuit = self._circuit("local")
            api_circuit = self._circuit("api")
            local_ok = str(local_circuit.get("state")) != "OPEN"
            if local_ok:
                local_ok = await self._local_probe()
            if local_ok and str(local_circuit.get("state")) == "HALF_OPEN":
                store = getattr(self, "circuit_store", None)
                if store is None or not await asyncio.to_thread(
                    store.acquire_probe,
                    "local",
                    self.local_provider_id,
                    event.unified_msg_origin,
                ):
                    local_ok = False
            if local_ok:
                local_ok = self._vram_allows_local()

            if not override and not local_ok and not self._is_owner(event):
                # Do not spend the owner's API budget for other users when
                # the local model is unavailable.
                await self._send_route_unavailable(event)
                return

            api_state = str(api_circuit.get("state"))
            api_open = api_state == "OPEN"
            if override:
                if api_open:
                    await self._send_route_unavailable(event)
                    return
                route = "cloud"
                agent_type = "cloud_override"
                source = override.get("source")
                until = override.get("until")
            elif local_ok:
                route = "local"
                agent_type = "main"
                source = ""
                until = ""
            elif not api_open:
                route = "cloud"
                agent_type = "main"
                source = "local_fallback"
                until = "turn_end"
            else:
                await self._send_route_unavailable(event)
                return

            if route == "cloud" and api_state == "HALF_OPEN":
                store = getattr(self, "circuit_store", None)
                if store is None or not await asyncio.to_thread(
                    store.acquire_probe,
                    "api",
                    self.cloud_provider_id,
                    event.unified_msg_origin,
                ):
                    await self._send_route_unavailable(event)
                    return

            if route == "local":
                event.set_extra("selected_provider", self.local_provider_id)
                if not api_open:
                    event.set_extra(
                        "router_fallback_provider_id", self.cloud_provider_id
                    )
            else:
                event.set_extra("selected_provider", self.cloud_provider_id)
                event.set_extra("router_cloud_provider", self.cloud_provider_id)
                event.set_extra("router_allow_fallback", False)
            event.set_extra("router_agent_type", agent_type)
            event.set_extra("router_attempt_callback", self._on_router_attempt)
            if source:
                event.set_extra("router_override_source", source)
            if until:
                event.set_extra("router_override_until", until)
            logger.info(
                "[router] route=%s reason=%s override=%s until=%s "
                "local_state=%s api_state=%s vram_free_mb=%s",
                route,
                source or ("local_ready" if route == "local" else "local_unavailable"),
                source or "-",
                until or "-",
                local_circuit.get("state"),
                api_circuit.get("state"),
                getattr(self, "_vram_free_mb", None),
            )
        except Exception as exc:
            logger.debug("[router] gate failed open: %s", exc)

    async def _send_route_unavailable(self, event: AstrMessageEvent) -> None:
        event.stop_event()
        if not event.is_private_chat():
            logger.info(
                "[router] group message ignored (no group policy configured)"
            )
            return
        text = (
            "服务暂时不可用，请稍后重试。"
            if self._lang(event) == "zh"
            else "Service temporarily unavailable. Please try again later."
        )
        await event.send(MessageChain().message(text))
