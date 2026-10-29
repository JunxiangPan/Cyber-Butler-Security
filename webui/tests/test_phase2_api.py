from __future__ import annotations

import sys
from pathlib import Path

from fastapi.testclient import TestClient

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE))

from app import create_app  # noqa: E402
from config import Settings  # noqa: E402
from services import WebServices  # noqa: E402


class FakeMailer:
    def __init__(self) -> None:
        self.sent: list[tuple[str, str]] = []

    async def send(self, email: str, code: str, ttl: int) -> None:
        self.sent.append((email, code))


class FakeServices:
    def __init__(self) -> None:
        self.sent: list[str] = []

    async def status(self) -> dict:
        return {"ok": True, "services": {"astrbot": True, "broker": True, "snowluma": False}, "checked_at": 1}

    async def temperatures(self) -> dict:
        return {"ok": True, "cpu": 55.0, "gpu": 43.0, "gpu_load": 12, "vram_used": 100, "vram_total": 1000}

    async def astrbot_plugins(self) -> dict:
        return {"ok": True, "count": 1, "plugins": [{"name": "demo", "activated": True}]}

    def logs(self, name: str, lines: int):
        return {"ok": True, "name": name, "available": True, "lines": ["line sk-secret123456", "path C:\\Users\\me\\secret.txt"]}

    async def send_chat(self, text: str) -> dict:
        self.sent.append(text)
        return {"ok": True, "sent": True}


def make_client(tmp_path: Path):
    settings = Settings(
        admin_email="owner@example.com",
        data_dir=tmp_path / "data",
        project_root=tmp_path,
        owner_umo="qq_test:FriendMessage:1",
        astrbot_token_file=tmp_path / "token",
    )
    settings.ensure_data()
    (tmp_path / "token").write_text("test-token", encoding="ascii")
    mailer = FakeMailer()
    services = FakeServices()
    return TestClient(create_app(settings, mailer, services)), mailer, services


def auth_headers(client: TestClient, mailer: FakeMailer) -> dict:
    client.post("/api/auth/request-otp", json={"email": "owner@example.com"})
    code = mailer.sent[-1][1]
    assert client.post("/api/auth/verify", json={"email": "owner@example.com", "code": code}).status_code == 200
    csrf = client.get("/api/auth/me").json()["csrf"]
    return {"X-CSRF-Token": csrf}


def test_phase2_read_endpoints_require_auth(tmp_path: Path) -> None:
    client, _, _ = make_client(tmp_path)
    for path in ("/api/status", "/api/temps", "/api/astrbot/plugins", "/api/logs?name=astrbot"):
        assert client.get(path).status_code == 401


def test_phase2_read_endpoints_and_log_redaction(tmp_path: Path) -> None:
    client, mailer, _ = make_client(tmp_path)
    auth_headers(client, mailer)
    status = client.get("/api/status")
    assert status.status_code == 200
    assert status.json()["services"]["broker"] is True
    assert client.get("/api/temps").json()["cpu"] == 55.0
    assert client.get("/api/astrbot/plugins").json()["count"] == 1

    logs = client.get("/api/logs?name=astrbot&lines=10")
    assert logs.status_code == 200
    assert client.get("/api/logs?name=..%2Fsecret").status_code == 400


def test_log_redaction_in_service(tmp_path: Path) -> None:
    settings = Settings(admin_email="owner@example.com", data_dir=tmp_path / "data", project_root=tmp_path)
    settings.ensure_data()
    log = tmp_path / "AstrBot" / "data" / "service-astrbot.out.log"
    log.parent.mkdir(parents=True)
    log.write_text("line sk-secret123456\npath C:\\Users\\me\\secret.txt\n", encoding="utf-8")
    result = WebServices(settings).logs("astrbot")
    text = "\n".join(result["lines"])
    assert "sk-secret" not in text
    assert "C:\\Users" not in text


def test_chat_requires_csrf_and_enforces_length_and_rate(tmp_path: Path) -> None:
    client, mailer, services = make_client(tmp_path)
    headers = auth_headers(client, mailer)
    assert client.post("/api/chat/send", json={"message": "hello"}).status_code == 403
    assert client.post(
        "/api/chat/send", json={"message": "x" * 501}, headers=headers
    ).status_code == 422
    for _ in range(5):
        assert client.post(
            "/api/chat/send", json={"message": "hello"}, headers=headers
        ).status_code == 200
    assert client.post(
        "/api/chat/send", json={"message": "hello"}, headers=headers
    ).status_code == 429
    assert services.sent == ["hello"] * 5
