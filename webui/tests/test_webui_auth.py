from __future__ import annotations

import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE))

from app import create_app  # noqa: E402
from settings import Settings  # noqa: E402


class FakeMailer:
    def __init__(self) -> None:
        self.sent: list[tuple[str, str]] = []

    async def send(self, email: str, code: str, ttl: int) -> None:
        self.sent.append((email, code))


def make_client(tmp_path: Path) -> tuple[TestClient, FakeMailer]:
    settings = Settings(admin_email="owner@example.com", data_dir=tmp_path / "data")
    settings.ensure_data()
    mailer = FakeMailer()
    app = create_app(settings, mailer)
    return TestClient(app), mailer


def test_otp_login_session_and_csrf_logout(tmp_path: Path) -> None:
    client, mailer = make_client(tmp_path)
    response = client.post("/api/auth/request-otp", json={"email": "owner@example.com"})
    assert response.status_code == 200
    assert len(mailer.sent) == 1
    _, code = mailer.sent[0]

    response = client.post(
        "/api/auth/verify", json={"email": "owner@example.com", "code": code}
    )
    assert response.status_code == 200
    set_cookie = response.headers["set-cookie"].lower()
    assert "httponly" in set_cookie
    assert "samesite=strict" in set_cookie
    assert "secure" not in set_cookie

    me = client.get("/api/auth/me")
    assert me.status_code == 200
    csrf = me.json()["csrf"]
    assert me.json()["email"] == "owner@example.com"

    assert client.post("/api/auth/logout").status_code == 403
    assert client.post("/api/auth/logout", headers={"X-CSRF-Token": csrf}).status_code == 200
    assert client.get("/api/auth/me").status_code == 401


def test_unregistered_email_is_generic_and_sends_nothing(tmp_path: Path) -> None:
    client, mailer = make_client(tmp_path)
    response = client.post("/api/auth/request-otp", json={"email": "other@example.com"})
    assert response.status_code == 200
    assert mailer.sent == []
    assert client.post(
        "/api/auth/verify", json={"email": "other@example.com", "code": "123456"}
    ).status_code == 401


def test_wrong_code_is_rejected_and_replay_is_rejected(tmp_path: Path) -> None:
    client, mailer = make_client(tmp_path)
    client.post("/api/auth/request-otp", json={"email": "owner@example.com"})
    _, code = mailer.sent[0]
    wrong = "000000" if code != "000000" else "111111"
    for _ in range(5):
        bad = client.post(
            "/api/auth/verify", json={"email": "owner@example.com", "code": wrong}
        )
        assert bad.status_code == 401

    client2, mailer2 = make_client(tmp_path / "second")
    client2.post("/api/auth/request-otp", json={"email": "owner@example.com"})
    _, code2 = mailer2.sent[0]
    assert client2.post(
        "/api/auth/verify", json={"email": "owner@example.com", "code": code2}
    ).status_code == 200
    assert client2.post(
        "/api/auth/verify", json={"email": "owner@example.com", "code": code2}
    ).status_code == 401


def test_otp_rate_limit(tmp_path: Path) -> None:
    client, _ = make_client(tmp_path)
    assert client.post(
        "/api/auth/request-otp", json={"email": "owner@example.com"}
    ).status_code == 200
    assert client.post(
        "/api/auth/request-otp", json={"email": "owner@example.com"}
    ).status_code == 429


def test_docs_and_openapi_are_disabled(tmp_path: Path) -> None:
    client, _ = make_client(tmp_path)
    assert client.get("/docs").status_code == 404
    assert client.get("/openapi.json").status_code == 404
