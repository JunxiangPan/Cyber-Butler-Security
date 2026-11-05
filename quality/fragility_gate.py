#!/usr/bin/env python3
"""Block acceptance scripts that cannot recover from TOTP replay defenses."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [ROOT / "tools" / "Run-Final-Acceptance.ps1", ROOT / "quality" / "Invoke-CbsVmAcceptance.ps1"]


def main() -> int:
    findings: list[str] = []
    for path in TARGETS:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if "/verify" not in text:
            continue
        if "429" not in text or "replay rejected" not in text:
            findings.append(f"{path.relative_to(ROOT)}: TOTP verify lacks 429/replay handling")
        if "Start-Sleep" not in text or "35" not in text:
            findings.append(f"{path.relative_to(ROOT)}: TOTP replay path lacks 35-second wait")
        if "Read-Host" not in text:
            findings.append(f"{path.relative_to(ROOT)}: replay path cannot request a fresh TOTP")
    if findings:
        print("FRAGILITY_GATE_FAILED")
        for item in findings:
            print("  " + item)
        return 1
    print("FRAGILITY_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
