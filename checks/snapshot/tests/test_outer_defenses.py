"""Outer defenses: installer entry point, update signature and health shape."""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_installer_is_not_a_powershell_bypass_shell() -> None:
    source = (ROOT / "build" / "CyberButlerLauncher.cs").read_text(encoding="utf-8-sig")
    assert "ExecutionPolicy Bypass" not in source
    assert "powershell.exe" not in source
    assert "RunspaceFactory" in source


def test_installer_binary_differs_from_service_launcher() -> None:
    a = (ROOT / "START-INSTALLER.exe").read_bytes()
    b = (ROOT / "tools" / "CyberButlerLauncher.exe").read_bytes()
    assert hashlib.sha256(a).digest() != hashlib.sha256(b).digest()


def test_update_verifies_manifest_signature() -> None:
    source = (ROOT / "tools" / "update.ps1").read_text(encoding="utf-8-sig")
    assert "verify_release.py" in source
    assert "signature verification failed" in source
    assert "update-manifest.sig" in source


def test_health_does_not_leak_service_identity() -> None:
    source = (ROOT / "tools" / "broker.py").read_text(encoding="utf-8")
    assert '"status": "ok"' in source
    assert '"service": "totp-broker"' not in source
