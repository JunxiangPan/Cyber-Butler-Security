"""Package-level checks for the synced router plugin source."""
from __future__ import annotations

import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROUTER = ROOT / "plugins" / "astrbot_plugin_router" / "main.py"


def test_router_package_has_new_gate_surface() -> None:
    source = ROUTER.read_text(encoding="utf-8")
    tree = ast.parse(source)
    names = {
        node.name
        for node in ast.walk(tree)
        if isinstance(node, (ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef))
    }
    assert "CircuitStore" in names
    assert "_warn_game_mode_stale" in names
    assert "gate" in names
    assert "router_command" in names
    assert "CONSENT_REQUIRED" not in source
    assert "game_mode" in source
    assert "router_attempt_callback" in source


def test_router_package_is_not_legacy_skeleton() -> None:
    source = ROUTER.read_text(encoding="utf-8")
    assert "only local HTTP signal ingestion" not in source
    assert "router_circuits" in source
    assert "legacy_provider_patch" in source
