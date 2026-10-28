"""TOTP anti-replay: the same valid code cannot be consumed twice."""

from __future__ import annotations

import broker


class FakeTOTP:
    def __init__(self, secret: str) -> None:
        self.secret = secret

    def verify(self, code: str, valid_window: int = 0) -> bool:
        return code == "123456" and valid_window == 1


def setup_function() -> None:
    broker._used_totp.clear()


def test_valid_totp_is_accepted_once(monkeypatch) -> None:
    monkeypatch.setattr(broker.pyotp, "TOTP", FakeTOTP)
    monkeypatch.setattr(broker, "secret", lambda: "test-secret")

    assert broker.verify_code("123456") == "totp"
    assert broker.verify_code("123456") == ""


def test_recovery_code_is_single_use(monkeypatch, tmp_path) -> None:
    import hashlib
    import json

    recovery = tmp_path / "recovery.json"
    digest = hashlib.sha256(b"ABCD1234").hexdigest()
    recovery.write_text(json.dumps({"sha256": [digest], "used": []}), encoding="utf-8")
    monkeypatch.setattr(broker, "RECOVERY_FILE", recovery)

    assert broker.verify_code("ABCD1234") == "recovery"
    assert broker.verify_code("ABCD1234") == ""
