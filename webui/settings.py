from __future__ import annotations

import json
import os
import secrets
from dataclasses import dataclass, field
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent


@dataclass
class Settings:
    admin_email: str
    data_dir: Path
    host: str = "127.0.0.1"
    port: int = 8765
    mailer_url: str = "http://127.0.0.1:8766/send-otp"
    cookie_secure: bool = False
    session_days: int = 7
    idle_hours: int = 8
    otp_ttl_seconds: int = 300
    otp_max_attempts: int = 5
    project_root: Path = field(default_factory=lambda: BASE_DIR.parent.parent)
    astrbot_api: str = "http://127.0.0.1:6185"
    astrbot_token_file: Path | None = None
    owner_umo: str = ""
    lhm_url: str = "http://127.0.0.1:18085/data.json"
    broker_port: int = 18090
    snowluma_port: int = 5099
    log_max_lines: int = 80
    local_app_data: str = field(
        default_factory=lambda: os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    )
    allowed_hosts: tuple[str, ...] = field(
        default_factory=lambda: ("127.0.0.1", "localhost")
    )

    @classmethod
    def load(cls, path: str | Path | None = None) -> "Settings":
        config_path = Path(path or os.environ.get("WEBUI_CONFIG") or BASE_DIR / "config.json")
        if not config_path.exists():
            raise FileNotFoundError(
                f"Web UI config not found: {config_path}. Copy config.example.json first."
            )
        raw = json.loads(config_path.read_text(encoding="utf-8"))
        data_dir = Path(raw.get("data_dir") or "data")
        if not data_dir.is_absolute():
            data_dir = BASE_DIR / data_dir
        project_root = Path(raw.get("project_root") or BASE_DIR.parent.parent)
        if not project_root.is_absolute():
            project_root = BASE_DIR / project_root
        token_file = raw.get("astrbot_token_file")
        token_path = Path(token_file) if token_file else project_root / ".astrbot_token"
        if not token_path.is_absolute():
            token_path = project_root / token_path
        settings = cls(
            admin_email=str(raw["admin_email"]).strip().lower(),
            data_dir=data_dir,
            host=str(raw.get("host") or "127.0.0.1"),
            port=int(raw.get("port") or 8765),
            mailer_url=str(raw.get("mailer_url") or "http://127.0.0.1:8766/send-otp"),
            cookie_secure=bool(raw.get("cookie_secure", False)),
            session_days=int(raw.get("session_days") or 7),
            idle_hours=int(raw.get("idle_hours") or 8),
            otp_ttl_seconds=int(raw.get("otp_ttl_seconds") or 300),
            otp_max_attempts=int(raw.get("otp_max_attempts") or 5),
            project_root=project_root,
            astrbot_api=str(raw.get("astrbot_api") or "http://127.0.0.1:6185"),
            astrbot_token_file=token_path,
            owner_umo=str(raw.get("owner_umo") or ""),
            lhm_url=str(raw.get("lhm_url") or "http://127.0.0.1:18085/data.json"),
            broker_port=int(raw.get("broker_port") or 18090),
            snowluma_port=int(raw.get("snowluma_port") or 5099),
            log_max_lines=int(raw.get("log_max_lines") or 80),
            allowed_hosts=tuple(raw.get("allowed_hosts") or ("127.0.0.1", "localhost")),
        )
        settings.ensure_data()
        return settings

    def ensure_data(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        for name in ("server_secret", "mailer_token"):
            path = self.data_dir / name
            if not path.exists():
                if name == "mailer_token":
                    path.write_text(secrets.token_hex(32), encoding="ascii")
                else:
                    path.write_bytes(secrets.token_bytes(32))
        try:
            self.mailer_token_path.chmod(0o600)
        except OSError:
            pass

    @property
    def db_path(self) -> Path:
        return self.data_dir / "webui.db"

    @property
    def server_secret(self) -> bytes:
        return (self.data_dir / "server_secret").read_bytes()

    @property
    def mailer_token_path(self) -> Path:
        return self.data_dir / "mailer_token"

    @property
    def mailer_token(self) -> str:
        return self.mailer_token_path.read_text(encoding="ascii").strip()

    @property
    def session_seconds(self) -> int:
        return self.session_days * 86400
