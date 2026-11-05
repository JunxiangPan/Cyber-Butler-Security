#!/usr/bin/env python3
"""Block acceptance scripts that reintroduce the 35-second replay workaround.

Replay protection is bound to (request_id, code). A fresh approval request
must not wait for a timer to reuse the same code.
"""
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
        if "Start-Sleep -Seconds 35" in text or "waiting 35 seconds" in text:
            findings.append(f"{path.relative_to(ROOT)}: 35-second TOTP wait is forbidden")
        if "replay rejected" in text and "Read-Host" in text:
            findings.append(f"{path.relative_to(ROOT)}: replay retry prompt is forbidden")
    if findings:
        print("FRAGILITY_GATE_FAILED")
        for item in findings:
            print("  " + item)
        return 1
    print("FRAGILITY_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
