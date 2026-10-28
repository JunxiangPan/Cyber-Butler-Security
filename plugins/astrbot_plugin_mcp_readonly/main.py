"""Keep Playwright MCP in read-only mode.

AstrBot re-adds MCP tools as active whenever the MCP server reconnects, so a
one-time dashboard toggle is not durable. This plugin periodically deactivates
the write-capable browser tools in memory.
"""

import asyncio

from astrbot import logger
from astrbot.api.star import Context, Star

BLOCKED = {
    "browser_click",
    "browser_type",
    "browser_evaluate",
    "browser_run_code_unsafe",
    "browser_file_upload",
    "browser_drop",
    "browser_fill_form",
    "browser_press_key",
    "browser_select_option",
    "browser_drag",
    "browser_hover",
    "browser_handle_dialog",
    "browser_emulate_media",
}


class McpReadonlyPlugin(Star):
    """Continuously deactivate write-capable Playwright MCP tools."""

    def __init__(self, context: Context) -> None:
        super().__init__(context)
        self._task: asyncio.Task | None = None

    async def initialize(self) -> None:
        self._task = asyncio.create_task(self._enforce())
        logger.info("[mcp_readonly] write-capable browser tools will stay disabled")

    async def _enforce(self) -> None:
        announced: set[str] = set()
        while True:
            try:
                manager = self.context.get_llm_tool_manager()
                for name in BLOCKED:
                    tool = manager.get_func(name)
                    if tool is None or not getattr(tool, "active", True):
                        continue
                    await manager.deactivate_llm_tool_async(name)
                    if name not in announced:
                        announced.add(name)
                        logger.info("[mcp_readonly] disabled %s", name)
            except Exception as exc:
                logger.warning("[mcp_readonly] enforce failed: %s", exc)
            await asyncio.sleep(20)
