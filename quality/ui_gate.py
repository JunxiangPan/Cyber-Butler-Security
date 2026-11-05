#!/usr/bin/env python3
"""Fail packaging when the console regresses to a bare form or dead UI code."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BANNED = ("AgentRuntime", "AuxRuntime", "GPU 显存", "插件市场", "人格与记忆")
ORPHAN_ROUTES = ("/api/temps", "/api/gpu", "/api/agent_runtime", "/api/plugins")
TEMPLATES = ROOT / "webui" / "templates"
UI_FILES = [
    *TEMPLATES.glob("*.html"),
    *(ROOT / "webui" / "static").glob("*.css"),
    *(ROOT / "webui" / "static").glob("*.js"),
    ROOT / "tools" / "cyber_butler_dashboard.ps1",
    *(ROOT / "tools").glob("dashboard_*.xaml"),
]


def main() -> int:
    findings: list[str] = []
    for path in UI_FILES:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for word in BANNED:
            if word in text:
                findings.append(f"{path.relative_to(ROOT)}: banned UI term {word}")
        if path.suffix == ".html":
            if ("<link" not in text or ".css" not in text) and "<style" not in text:
                findings.append(f"{path.relative_to(ROOT)}: no stylesheet")
            if len(text.strip()) < 800:
                findings.append(f"{path.relative_to(ROOT)}: template too small")
    app = (ROOT / "webui" / "app.py").read_text(encoding="utf-8")
    for route in ORPHAN_ROUTES:
        if f'"{route}"' in app:
            findings.append(f"webui/app.py: orphan UI API {route}")
    if findings:
        print("UI_GATE_FAILED")
        for item in findings:
            print("  " + item)
        return 1
    print("UI_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
