"""Small remaining business branches: approval status, adapter, TOTP payload."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


def test_get_approval_status_branches(monkeypatch) -> None:
    assert broker.get_approval_status("")[0] == 400
    monkeypatch.setattr(broker, "_get_approval_state", lambda cid: None)
    assert broker.get_approval_status("missing")[0] == 404
    monkeypatch.setattr(broker, "_get_approval_state", lambda cid: {"status": "approved", "scoped_token": "tok", "scoped_expires_in": 3, "scoped_root": "root"})
    status, body = broker.get_approval_status("ok")
    assert status == 200 and body["scoped_token"] == "tok"


def test_run_approval_request_adapter(monkeypatch) -> None:
    monkeypatch.setattr(broker, "run_request", lambda body: (200, {"status": "requires_totp"}))
    assert broker.run_approval_request({"x": 1})[0] == 200
    monkeypatch.setattr(broker, "run_request", lambda body: (200, {"status": "bad"}))
    assert broker.run_approval_request({"x": 1})[0] == 500
    monkeypatch.setattr(broker, "run_request", lambda body: (403, {"error": "denied"}))
    assert broker.run_approval_request({"x": 1})[0] == 403
    monkeypatch.setattr(broker, "run_request", lambda body: (429, {"error": "slow"}))
    assert broker.run_approval_request({"x": 1})[0] == 429


def test_totp_binding_payload(monkeypatch) -> None:
    monkeypatch.setattr(broker, "secret", lambda: "JBSWY3DPEHPK3PXP")
    monkeypatch.setattr(broker, "_totp_qr", lambda uri: "base64")
    payload = broker.totp_binding_payload()
    assert payload["otpauth_uri"].startswith("otpauth://totp/")
    assert payload["qr_png_base64"] == "base64"
