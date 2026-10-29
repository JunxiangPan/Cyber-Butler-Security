"""Contract test for the URL/outside-shared send approval path.

The overlay classifies URLs and files outside the shared folder as risky and
calls the Broker with a complete manifest. The Broker must issue a TOTP
challenge for that manifest instead of returning the old unconditional 403.
"""

from __future__ import annotations

import hashlib
import time
from pathlib import Path

import broker

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / "overlay" / "astrbot" / "core" / "tools" / "message_tools.py"


def setup_function() -> None:
    broker._pending = None
    broker._send_events.clear()
    broker._send_results.clear()
    broker._verify_locked_until = 0.0
    broker._global_failures = 0
    broker._global_lock_until = 0.0
    broker._last_request_at = 0.0


def _file_entry(path: Path) -> dict:
    data = path.read_bytes()
    return {
        "kind": "file",
        "path": str(path.resolve()),
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def test_overlay_routes_urls_and_outside_paths_to_totp() -> None:
    source = OVERLAY.read_text(encoding="utf-8")
    assert 'risky, reason = True, "远程 URL 文件"' in source
    assert "url_target" in source
    assert "_totp_request_send(" in source


def test_broker_challenges_an_outside_manifest(monkeypatch, tmp_path) -> None:
    outside = tmp_path / "workspace-generated.png"
    outside.write_bytes(b"generated")
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    monkeypatch.setattr(broker, "TIMEOUT_SECONDS", 0.01)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)

    status, body = broker.run_request(
        {
            "action": "send",
            "target": str(outside),
            "manifest": [_file_entry(outside)],
        }
    )

    assert status == 408  # challenge sent, then the short test timeout expires
    assert body.get("approved") is False
    assert broker._pending is None
