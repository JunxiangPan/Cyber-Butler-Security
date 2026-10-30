"""Read-only command execution for the /dsh bridge."""

from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable

from .audit import AuditError, AuditWriter
from .commands import Command
from .formatting import format_health, format_logs, format_status
from .sources import (
    BridgeUnavailable,
    PortResult,
    collect_providers,
    probe_ports,
    read_log_tail,
    read_router_state,
)

logger = logging.getLogger(__name__)

SOURCE_UNAVAILABLE_REPLY = "读取失败，已拒绝。"
INTERNAL_ERROR_REPLY = "内部错误，已拒绝。"


class DshService:
    """Execute exactly status, health and logs with fixed read-only sources.

    There is deliberately no DSH 3188 precheck: every current command is
    read-only, so a DSH failure must not hide status or log diagnostics. A
    future write command must add its own fail-closed precheck before acting.
    """

    def __init__(
        self,
        *,
        provider_manager: object,
        router_db_path: object,
        log_path: object,
        audit: AuditWriter | None,
        probe_fn: Callable[[], Awaitable[list[PortResult]]] | None = None,
    ) -> None:
        self.provider_manager = provider_manager
        self.router_db_path = router_db_path
        self.log_path = log_path
        self.audit = audit
        self.probe_fn = probe_fn or probe_ports

    async def run(self, command: Command) -> tuple[str, str]:
        """Execute one parsed command and append its audit result.

        Args:
            command: Parsed command.

        Returns:
            (reply, result) where result is one of the audit values.

        Raises:
            AuditError: The audit sink is unavailable; no reply may be sent.
        """
        reply, result = await self._execute(command)
        if self.audit is None:
            raise AuditError("audit sink is unavailable")
        self.audit.write(command.kind, result)
        return reply, result

    async def _execute(self, command: Command) -> tuple[str, str]:
        if command.kind not in {"status", "health", "logs"}:
            return INTERNAL_ERROR_REPLY, "error"

        try:
            if command.kind == "status":
                providers = collect_providers(self.provider_manager)
                state = read_router_state(self.router_db_path)
                return format_status(providers, state), "ok"

            if command.kind == "health":
                results = await self.probe_fn()
                if not results:
                    raise BridgeUnavailable("health probe returned no results")
                result = "ok" if all(item.up for item in results) else "degraded"
                return format_health(results), result

            lines = read_log_tail(self.log_path, command.n)
            return format_logs(lines, command.n), "ok"
        except BridgeUnavailable:
            logger.warning("/dsh source unavailable", exc_info=True)
            return SOURCE_UNAVAILABLE_REPLY, "unavailable"
        except Exception:  # noqa: BLE001 - never leak internals to QQ
            logger.exception("/dsh command failed")
            return INTERNAL_ERROR_REPLY, "error"
