"""Read-only data sources for status, health and logs."""

from __future__ import annotations

import asyncio
import sqlite3
import stat
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

MAX_LOG_BYTES = 256 * 1024
MAX_LOG_LINES = 200
HEALTH_PORTS: tuple[tuple[int, str], ...] = (
    (6185, "AstrBot"),
    (18090, "TOTP Broker"),
    (8765, "Cyber-Butler Web UI"),
    (8766, "OTP Mailer"),
)


class BridgeUnavailable(RuntimeError):
    """A required read-only source is unavailable; the command must fail closed."""


@dataclass(frozen=True)
class ProviderInfo:
    provider_id: str
    provider_type: str
    enabled: bool
    model: str


@dataclass(frozen=True)
class RouterState:
    state_version: int
    local_mode: str
    game_mode: str
    game_mode_since: float
    updated_at: str


@dataclass(frozen=True)
class PortResult:
    port: int
    service: str
    up: bool
    latency_ms: int


def _text(value: Any) -> str:
    return str(value).strip() if value is not None else ""


def collect_providers(provider_manager: Any) -> list[ProviderInfo]:
    """Read provider IDs, types, enabled flags and models from memory.

    Args:
        provider_manager: AstrBot ProviderManager instance.

    Returns:
        A stable list of provider summaries, with no config secrets.

    Raises:
        BridgeUnavailable: The manager or its instance map is unavailable.
    """
    if provider_manager is None:
        raise BridgeUnavailable("provider manager is unavailable")
    try:
        inst_map = getattr(provider_manager, "inst_map", None)
        if not isinstance(inst_map, dict) or not inst_map:
            raise BridgeUnavailable("provider instance map is empty")
        items = list(inst_map.items())
    except BridgeUnavailable:
        raise
    except Exception as exc:  # noqa: BLE001 - fail closed on a broken manager
        raise BridgeUnavailable("provider manager read failed") from exc

    result: list[ProviderInfo] = []
    for key, instance in items:
        config = getattr(instance, "provider_config", None)
        if not isinstance(config, dict):
            config = {}
        provider_id = _text(config.get("id") or key)
        provider_type = _text(config.get("type") or config.get("provider_type"))
        if not provider_type:
            meta = getattr(instance, "meta", None)
            if callable(meta):
                try:
                    provider_type = _text(getattr(meta(), "type", ""))
                except Exception:  # noqa: BLE001 - display fallback only
                    provider_type = ""
        enabled = bool(config.get("enable", True))
        model = _text(
            config.get("model")
            or config.get("embedding_model")
            or config.get("rerank_model")
            or getattr(instance, "model_name", "")
        )
        if not model:
            get_model = getattr(instance, "get_model", None)
            if callable(get_model):
                try:
                    model = _text(get_model())
                except Exception:  # noqa: BLE001 - display fallback only
                    model = ""
        result.append(
            ProviderInfo(
                provider_id=provider_id or "unknown",
                provider_type=provider_type or "unknown",
                enabled=enabled,
                model=model,
            )
        )
    if not result:
        raise BridgeUnavailable("provider list is empty")
    result.sort(key=lambda item: (item.provider_id.lower(), item.provider_type))
    return result


def read_router_state(db_path: Path) -> RouterState:
    """Read the single router_state row without writing to the database.

    Args:
        db_path: AstrBot main SQLite database containing router_state.

    Returns:
        The current router state.

    Raises:
        BridgeUnavailable: The database/table/row cannot be read.
    """
    path = Path(db_path)
    if not path.is_file():
        raise BridgeUnavailable("router state database is missing")
    connection = None
    try:
        connection = sqlite3.connect(
            f"file:{path.as_posix()}?mode=ro",
            uri=True,
            timeout=1.0,
        )
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA query_only=ON")
        row = connection.execute(
            "SELECT state_version, local_mode, game_mode, game_mode_since, "
            "updated_at FROM router_state WHERE id=1"
        ).fetchone()
        if row is None:
            raise BridgeUnavailable("router_state row is missing")
        return RouterState(
            state_version=int(row["state_version"]),
            local_mode=_text(row["local_mode"]) or "unknown",
            game_mode=_text(row["game_mode"]) or "off",
            game_mode_since=float(row["game_mode_since"] or 0.0),
            updated_at=_text(row["updated_at"]),
        )
    except BridgeUnavailable:
        raise
    except (OSError, sqlite3.Error, TypeError, ValueError) as exc:
        raise BridgeUnavailable("router state read failed") from exc
    finally:
        if connection is not None:
            connection.close()


async def check_tcp(host: str, port: int, timeout: float = 0.3) -> bool:
    """Check whether a TCP endpoint accepts a connection.

    Args:
        host: Endpoint host.
        port: Endpoint port.
        timeout: Connect timeout in seconds.

    Returns:
        True when the connection succeeds, otherwise False.
    """
    writer = None
    try:
        _, writer = await asyncio.wait_for(
            asyncio.open_connection(host, int(port)),
            timeout=timeout,
        )
        return True
    except (OSError, asyncio.TimeoutError):
        return False
    finally:
        if writer is not None:
            writer.close()
            try:
                await writer.wait_closed()
            except (OSError, RuntimeError):
                pass


async def probe_ports(
    ports: tuple[tuple[int, str], ...] = HEALTH_PORTS,
    timeout: float = 1.0,
) -> list[PortResult]:
    """Probe fixed loopback ports concurrently without sending HTTP data.

    Args:
        ports: Port/service pairs.
        timeout: Per-port connect timeout in seconds.

    Returns:
        One result per requested port, ordered like the input.
    """

    async def _probe(port: int, service: str) -> PortResult:
        started = time.perf_counter()
        writer = None
        up = False
        try:
            _, writer = await asyncio.wait_for(
                asyncio.open_connection("127.0.0.1", int(port)),
                timeout=timeout,
            )
            up = True
        except (OSError, asyncio.TimeoutError):
            up = False
        finally:
            if writer is not None:
                writer.close()
                try:
                    await writer.wait_closed()
                except (OSError, RuntimeError):
                    pass
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        return PortResult(
            port=int(port),
            service=service,
            up=up,
            latency_ms=max(0, elapsed_ms),
        )

    return list(await asyncio.gather(*(_probe(port, name) for port, name in ports)))


def read_log_tail(path: Path, n: int) -> list[str]:
    """Read the last n lines from one fixed regular file.

    Args:
        path: Fixed log path.
        n: Number of lines, from 1 to 200.

    Returns:
        The tail lines, oldest first.

    Raises:
        BridgeUnavailable: The path is missing, not a regular file, a symlink,
            or cannot be read.
        ValueError: n is outside 1..200.
    """
    if not isinstance(n, int) or not 1 <= n <= MAX_LOG_LINES:
        raise ValueError("n must be between 1 and 200")
    log_path = Path(path)
    try:
        info = log_path.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            raise BridgeUnavailable("log path is not a regular file")
        if info.st_size == 0:
            return []
        start = max(0, info.st_size - MAX_LOG_BYTES)
        with log_path.open("rb") as handle:
            handle.seek(start)
            payload = handle.read()
    except BridgeUnavailable:
        raise
    except (OSError, ValueError) as exc:
        raise BridgeUnavailable("log file is unavailable") from exc
    text = payload.decode("utf-8", errors="replace")
    lines = text.splitlines()
    if start > 0 and lines:
        lines = lines[1:]
    return lines[-n:]
