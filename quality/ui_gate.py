#!/usr/bin/env python3
"""UI gate: styled console, no dead UI terms/routes, no orphan UI assets."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BANNED = ("AgentRuntime", "AuxRuntime", "GPU 显存", "插件市场", "人格与记忆")
ORPHAN_ROUTES = ("/api/temps", "/api/gpu", "/api/agent_runtime", "/api/plugins")
TEMPLATES = ROOT / "webui" / "templates"
STATIC = ROOT / "webui" / "static"
LEGACY_NAMES = re.compile(r"runtime|persona|plugin|model", re.IGNORECASE)
LEGACY_ALLOW = {"harden_broker_runtime.ps1"}
ENTRY_FILES = [ROOT / "tools" / "cyber_butler_dashboard.ps1", ROOT / "tools" / "start-dashboard.ps1", ROOT / "installer" / "Install-CyberButler.ps1", ROOT / "installer" / "lib" / "Installer.Core.ps1"]
WPF_MODULES = [*sorted((ROOT / "tools").glob("dashboard_*.ps1")), *sorted((ROOT / "tools").glob("plugin_*.ps1")), *sorted((ROOT / "tools").glob("*.xaml"))]


def _static_refs() -> set[str]:
    refs: set[str] = set()
    for template in TEMPLATES.glob("*.html"):
        text = template.read_text(encoding="utf-8", errors="replace")
        for value in re.findall(r'(?:src|href)="(/static/[^"]+)"', text):
            refs.add(value.removeprefix("/static/").lstrip("/"))
    return refs


def main() -> int:
    findings: list[str] = []
    refs = _static_refs()
    for path in STATIC.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(STATIC).as_posix()
        if rel.startswith("i18n/"):
            continue
        if rel not in refs:
            findings.append(f"webui/static/{rel}: orphan static asset (no template src/href)")
    for path in WPF_MODULES:
        name = path.name
        referenced = any(entry.is_file() and name in entry.read_text(encoding="utf-8", errors="replace") for entry in ENTRY_FILES)
        if not referenced:
            findings.append(f"tools/{name}: orphan WPF module (not referenced by entry/launcher)")
    for root_name in ("tools", "webui"):
        for path in (ROOT / root_name).rglob("*"):
            if not path.is_file() or path.name in LEGACY_ALLOW:
                continue
            if ".venv" in path.parts or "__pycache__" in path.parts:
                continue
            if LEGACY_NAMES.search(path.name):
                findings.append(f"{path.relative_to(ROOT).as_posix()}: legacy UI filename term")
    app = (ROOT / "webui" / "app.py").read_text(encoding="utf-8")
    for route in ORPHAN_ROUTES:
        if f'"{route}"' in app:
            findings.append(f"webui/app.py: orphan UI API {route}")
    for path in [*TEMPLATES.glob("*.html"), *STATIC.glob("*.css"), *STATIC.glob("*.js"), ROOT / "tools" / "cyber_butler_dashboard.ps1"]:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for word in BANNED:
            if word in text:
                findings.append(f"{path.relative_to(ROOT).as_posix()}: banned UI term {word}")
        if path.suffix == ".html" and ("<link" not in text or ".css" not in text) and "<style" not in text:
            findings.append(f"{path.relative_to(ROOT).as_posix()}: no stylesheet")
    if findings:
        print("UI_GATE_FAILED")
        for item in findings:
            print("  " + item)
        return 1
    print("UI_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
