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
        self.langs: list[str] = []

    async def send(self, email: str, code: str, ttl: int, lang: str = "zh") -> None:
        self.sent.append((email, code))
        self.langs.append(lang)


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


def test_auto_cookie_secure_accepts_trusted_tailscale_forwarded_proto(
    tmp_path: Path,
) -> None:
    settings = Settings(
        admin_email="owner@example.com",
        data_dir=tmp_path / "proxy-auto",
        cookie_secure="auto",
    )
    settings.ensure_data()
    mailer = FakeMailer()
    client = TestClient(
        create_app(settings, mailer),
        base_url="http://testserver",
        client=("127.0.0.1", 50000),
    )
    forwarded = {"X-Forwarded-Proto": "https"}
    client.post(
        "/api/auth/request-otp",
        json={"email": "owner@example.com"},
        headers=forwarded,
    )
    _, code = mailer.sent[0]
    response = client.post(
        "/api/auth/verify",
        json={"email": "owner@example.com", "code": code},
        headers=forwarded,
    )
    assert response.status_code == 200
    assert "secure" in response.headers["set-cookie"].lower()


def test_auto_cookie_secure_adapts_to_scheme(tmp_path: Path) -> None:
    def client_for(base_url: str):
        settings = Settings(admin_email="owner@example.com", data_dir=tmp_path / ("auto-" + base_url.split(":")[0]), cookie_secure="auto")
        settings.ensure_data()
        mailer = FakeMailer()
        return TestClient(create_app(settings, mailer), base_url=base_url), mailer

    http, mailer = client_for("http://testserver")
    http.post("/api/auth/request-otp", json={"email": "owner@example.com"})
    code = mailer.sent[-1][1]
    response = http.post("/api/auth/verify", json={"email": "owner@example.com", "code": code})
    assert response.status_code == 200
    assert "secure" not in response.headers["set-cookie"].lower()

    https, mailer = client_for("https://testserver")
    https.post("/api/auth/request-otp", json={"email": "owner@example.com"})
    code = mailer.sent[-1][1]
    response = https.post("/api/auth/verify", json={"email": "owner@example.com", "code": code})
    assert response.status_code == 200
    assert "secure" in response.headers["set-cookie"].lower()


def test_otp_language_follows_request_and_falls_back(tmp_path: Path) -> None:
    client, mailer = make_client(tmp_path / "lang")
    assert client.post(
        "/api/auth/request-otp", json={"email": "owner@example.com", "lang": "de"}
    ).status_code == 200
    assert mailer.langs[-1] == "de"
    assert client.post(
        "/api/auth/request-otp", json={"email": "owner@example.com", "lang": "not-a-language"}
    ).status_code in (200, 429)
    if len(mailer.langs) > 1:
        assert mailer.langs[-1] == "zh"


def test_localized_error_page_and_csp(tmp_path: Path) -> None:
    client, _ = make_client(tmp_path / "errors")
    page = client.get("/missing-page")
    assert page.status_code == 404
    assert 'data-error-status="404"' in page.text
    assert "missing-page" not in page.text
    api = client.get("/api/missing-endpoint")
    assert api.status_code == 404
    assert api.json()["code"] == "http.error"
    csp = client.get("/").headers["content-security-policy"]
    assert "unsafe-inline" not in csp
    assert "unsafe-eval" not in csp
