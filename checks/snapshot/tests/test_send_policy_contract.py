"""Contract test for the URL/outside-shared send approval path.

The overlay classifies URLs and files outside the shared folder as risky and
calls the Broker with a complete manifest. The Broker must issue a TOTP
challenge for that manifest instead of returning the old unconditional 403.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import broker

ROOT = Path(__file__).resolve().parents[1]


def setup_function() -> None:
    broker.broker_state._pending = None
    broker._send_events.clear()
    broker._send_results.clear()
    broker.broker_state._verify_locked_until = 0.0
    broker.broker_state._global_failures = 0
    broker.broker_state._global_lock_until = 0.0
    broker.broker_state._last_request_at = 0.0


def _file_entry(path: Path) -> dict:
    data = path.read_bytes()
    return {
        "kind": "file",
        "path": str(path.resolve()),
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


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

    assert status == 200
    assert body.get("status") in {"requires_totp", "approved"}
