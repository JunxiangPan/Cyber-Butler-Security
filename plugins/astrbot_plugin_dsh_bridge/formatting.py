"""Compact QQ-safe renderers for /dsh replies."""

from __future__ import annotations

from datetime import datetime

from .redact import redact_line, truncate_text
from .sources import PortResult, ProviderInfo, RouterState

STATUS_LIMIT = 1200
HEALTH_LIMIT = 600
LOGS_LIMIT = 3500
MAX_PROVIDER_LINES = 20


def _clean(value: object, limit: int = 80) -> str:
    text = " ".join(str(value or "").split())
    return text[:limit]


def _now() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")


def format_status(providers: list[ProviderInfo], state: RouterState) -> str:
    """Render provider and router summaries without config/secret fields.

    Args:
        providers: Read-only provider summaries.
        state: Current router state.

    Returns:
        A truncated plain-text status reply.
    """
    enabled = sum(1 for item in providers if item.enabled)
    lines = [
        f"DSH status {_now()}",
        f"Providers: {enabled}/{len(providers)} enabled",
    ]
    for item in providers[:MAX_PROVIDER_LINES]:
        flags = "enabled" if item.enabled else "disabled"
        model = f" model={_clean(item.model)}" if item.model else ""
        lines.append(
            f"- {_clean(item.provider_id)} ({_clean(item.provider_type)}) "
            f"{flags}{model}"
        )
    if len(providers) > MAX_PROVIDER_LINES:
        lines.append(f"... +{len(providers) - MAX_PROVIDER_LINES} more")
    lines.append(
        f"Router: v{state.state_version} local={_clean(state.local_mode)} "
        f"game={_clean(state.game_mode)}"
    )
    if state.updated_at:
        lines.append(f"Updated: {_clean(state.updated_at, 64)}")
    return truncate_text("\n".join(lines), STATUS_LIMIT)


def format_health(results: list[PortResult]) -> str:
    """Render fixed loopback port probes.

    Args:
        results: Probe results.

    Returns:
        A truncated plain-text health reply.
    """
    lines = [f"DSH health {_now()}"]
    for item in results:
        state = "up" if item.up else "down"
        lines.append(f"{item.port} {_clean(item.service)} {state} {item.latency_ms}ms")
    return truncate_text("\n".join(lines), HEALTH_LIMIT)


def format_logs(lines: list[str], n: int) -> str:
    """Render a redacted log tail with hard line and total caps.

    Args:
        lines: Raw tail lines, oldest first.
        n: Requested line count.

    Returns:
        A truncated plain-text log reply.
    """
    header = f"logs console-final.err.log last {len(lines)}/{n} lines"
    if not lines:
        return f"{header}\n(empty)"
    body = "\n".join(redact_line(line) for line in lines)
    return truncate_text(f"{header}\n{body}", LOGS_LIMIT)
