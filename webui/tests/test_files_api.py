from __future__ import annotations

import os
import sys
from pathlib import Path

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


class FakeServices:
    async def usage(self):
        return {"ok": True, "tokens": 123, "calls": 2, "cost": 0.01, "providers": [], "unpriced": [], "pricing_configured": True}

    def backups(self):
        return {"ok": True, "available": True, "items": [{"name": "b1", "kind": "directory", "size": 10, "mtime": 1}], "total": 10}

    async def security_pending(self):
        return {"ok": True, "available": True, "pending": False}


def make_client(tmp_path: Path):
    root = tmp_path / "shared"
    root.mkdir()
    (root / "ok.txt").write_text("hello", encoding="utf-8")
    (root / "run.exe").write_text("bad", encoding="utf-8")
    (root / "script.py").write_text("bad", encoding="utf-8")
    (root / "big.bin").write_bytes(b"x" * (1024 * 1024 + 10))
    (root / "sub").mkdir()
    settings = Settings(
        admin_email="owner@example.com",
        data_dir=tmp_path / "data",
        project_root=tmp_path,
        file_root=str(root),
        file_max_mb=1,
    )
    settings.ensure_data()
    mailer = FakeMailer()
    return TestClient(create_app(settings, mailer, FakeServices())), mailer


def auth(client: TestClient, mailer: FakeMailer) -> dict:
    client.post("/api/auth/request-otp", json={"email": "owner@example.com"})
    code = mailer.sent[-1][1]
    assert client.post("/api/auth/verify", json={"email": "owner@example.com", "code": code}).status_code == 200
    return {"X-CSRF-Token": client.get("/api/auth/me").json()["csrf"]}


def test_file_list_hides_executables_and_blocks_traversal(tmp_path: Path) -> None:
    client, mailer = make_client(tmp_path)
    auth(client, mailer)
    listing = client.get("/api/files/list")
    assert listing.status_code == 200
    names = {item["name"] for item in listing.json()["entries"]}
    assert "ok.txt" in names
    assert "run.exe" not in names
    assert "script.py" not in names
    assert "sub" in names
    for bad in ("..", "../", "C:/Windows/win.ini", "/etc/passwd", "sub/../../ok.txt"):
        assert client.get("/api/files/list", params={"path": bad}).status_code == 403
    audit = (tmp_path / "data" / "files-audit.log").read_text(encoding="utf-8")
    assert "reason=" in audit


def test_file_download_is_read_only_and_limited(tmp_path: Path) -> None:
    client, mailer = make_client(tmp_path)
    auth(client, mailer)
    ok = client.get("/api/files/download", params={"path": "ok.txt"})
    assert ok.status_code == 200
    assert ok.text == "hello"
    assert client.get("/api/files/download", params={"path": "run.exe"}).status_code == 403
    assert client.get("/api/files/download", params={"path": "script.py"}).status_code == 403
    assert client.get("/api/files/download", params={"path": "big.bin"}).status_code == 403
    assert client.get("/api/files/download", params={"path": "missing.txt"}).status_code == 403
    assert client.post("/api/files/list").status_code == 405


def test_usage_backups_pending_are_read_only(tmp_path: Path) -> None:
    client, mailer = make_client(tmp_path)
    auth(client, mailer)
    assert client.get("/api/usage").json()["tokens"] == 123
    assert client.get("/api/backups").json()["items"][0]["name"] == "b1"
    assert client.get("/api/security/pending").json()["pending"] is False


def test_file_root_reloads_from_config(tmp_path: Path) -> None:
    first = tmp_path / "first"
    second = tmp_path / "second"
    first.mkdir()
    second.mkdir()
    (second / "new.txt").write_text("new", encoding="utf-8")
    config = tmp_path / "webui-config.json"
    config.write_text('{"file_root": "%s"}' % str(first).replace("\\", "\\\\"), encoding="utf-8")
    settings = Settings(admin_email="owner@example.com", data_dir=tmp_path / "data", config_path=config, file_root=str(first))
    from file_manager import FileManager
    manager = FileManager(settings)
    assert manager.list_dir()["entries"] == []
    config.write_text('{"file_root": "%s"}' % str(second).replace("\\", "\\\\"), encoding="utf-8")
    assert [item["name"] for item in manager.list_dir()["entries"]] == ["new.txt"]
