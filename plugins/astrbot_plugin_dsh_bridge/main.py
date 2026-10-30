"""Owner-only, read-only /dsh bridge plugin."""

from __future__ import annotations

from pathlib import Path

from astrbot.api import logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.message_components import Plain
from astrbot.api.star import Context, Star
from astrbot.core.utils.astrbot_path import get_astrbot_data_path

from .audit import AuditError, AuditWriter
from .auth import is_owner_event, parse_owner_ids, parse_platform_names
from .commands import USAGE, parse_command
from .service import DshService
from .sources import HEALTH_PORTS, probe_ports

DATA_DIR = Path(get_astrbot_data_path())
ROUTER_DB_PATH = DATA_DIR / "data_v4.db"
LOG_PATH = DATA_DIR / "console-final.err.log"
AUDIT_PATH = Path(r"C:\ProgramData\CyberButler\audit\ops.jsonl")


def _raw_message_text(event: AstrMessageEvent) -> str:
    """Return the original plain-text chain before wake-prefix stripping.

    Args:
        event: AstrBot message event.

    Returns:
        Joined plain-text components, or the event's current message string.
    """
    try:
        components = event.get_messages()
        text = "".join(
            str(component.text)
            for component in components
            if isinstance(component, Plain)
        ).strip()
        if text:
            return text
    except Exception:  # noqa: BLE001 - fall back to the stripped string
        pass
    return str(getattr(event, "message_str", "") or "").strip()


class DshBridge(Star):
    def __init__(self, context: Context, config: dict | None = None) -> None:
        super().__init__(context)
        values = config or {}
        self.owner_ids = parse_owner_ids(values.get("owner_ids", ""))
        self.platform_names = parse_platform_names(values.get("platform_names") or None)
        self.audit: AuditWriter | None = None
        try:
            self.audit = AuditWriter(AUDIT_PATH)
        except AuditError:
            logger.exception("audit sink is unavailable; /dsh commands will be refused")
        if not self.owner_ids:
            logger.warning("no owner_ids configured; all /dsh commands will be denied")
        self.service = DshService(
            provider_manager=getattr(context, "provider_manager", None),
            router_db_path=ROUTER_DB_PATH,
            log_path=LOG_PATH,
            audit=self.audit,
            probe_fn=lambda: probe_ports(HEALTH_PORTS),
        )

    @filter.event_message_type(filter.EventMessageType.ALL, priority=30000)
    async def dsh_command(self, event: AstrMessageEvent) -> None:
        """Handle only exact /dsh commands and stop the event from reaching LLMs.

        Args:
            event: AstrBot message event.
        """
        text = _raw_message_text(event)
        if not text.startswith("/dsh"):
            return

        if not is_owner_event(event, self.owner_ids, self.platform_names):
            self._audit_quiet("unknown", "denied")
            event.stop_event()
            return

        command = parse_command(text)
        if command is None:
            if not self._audit_quiet("unknown", "invalid"):
                event.stop_event()
                return
            try:
                await event.send(event.plain_result(USAGE))
            except Exception:  # noqa: BLE001 - never let a send failure reach the LLM
                logger.exception("failed to send /dsh usage")
            finally:
                event.stop_event()
            return

        try:
            reply, _result = await self.service.run(command)
        except AuditError:
            logger.exception("audit sink failed; /dsh command refused")
            event.stop_event()
            return

        try:
            await event.send(event.plain_result(reply))
        except Exception:  # noqa: BLE001 - the event must stay stopped
            logger.exception("failed to send /dsh reply")
        finally:
            event.stop_event()

    def _audit_quiet(self, command: str, result: str) -> bool:
        """Append an audit record without exposing the failure to the sender.

        Args:
            command: Canonical audit command.
            result: Canonical audit result.

        Returns:
            True when the record was written, otherwise False.
        """
        if self.audit is None:
            return False
        try:
            self.audit.write(command, result)
            return True
        except AuditError:
            logger.exception("audit append failed")
            return False
