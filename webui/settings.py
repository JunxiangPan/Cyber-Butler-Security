from __future__ import annotations

import json
import os
import secrets
from dataclasses import dataclass, field
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent


@dataclass
class Settings:
    """Settings helper/type."""
    admin_email: str
    data_dir: Path
    config_path: Path | None = None
    host: str = "127.0.0.1"
    port: int = 8765
    mailer_url: str = "http://127.0.0.1:8766/send-otp"
    cookie_secure: bool | str = False
    session_days: int = 7
    idle_hours: int = 8
    otp_ttl_seconds: int = 300
    otp_max_attempts: int = 5
    project_root: Path = field(default_factory=lambda: BASE_DIR.parent.parent)
    broker_port: int = 18090
    log_max_lines: int = 80
    file_root: str = ""
    file_max_mb: int = 20
    file_deny_patterns: tuple[str, ...] = (
        "*.key", "*.pem", "*.pfx", "*.p12", "*secret*", "*password*", "*token*",
    )
    allowed_hosts: tuple[str, ...] = field(
        default_factory=lambda: ("127.0.0.1", "localhost")
    )

    @classmethod
    def load(cls, path: str | Path | None = None) -> "Settings":
        """Load.
        
        Args:
            path: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
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
        raw_cookie_secure = raw.get("cookie_secure", False)
        if isinstance(raw_cookie_secure, str) and raw_cookie_secure.strip().lower() == "auto":
            cookie_secure: bool | str = "auto"
        else:
            cookie_secure = bool(raw_cookie_secure)
        settings = cls(
            admin_email=str(raw["admin_email"]).strip().lower(),
            data_dir=data_dir,
            host=str(raw.get("host") or "127.0.0.1"),
            port=int(raw.get("port") or 8765),
            mailer_url=str(raw.get("mailer_url") or "http://127.0.0.1:8766/send-otp"),
            cookie_secure=cookie_secure,
            session_days=int(raw.get("session_days") or 7),
            idle_hours=int(raw.get("idle_hours") or 8),
            otp_ttl_seconds=int(raw.get("otp_ttl_seconds") or 300),
            otp_max_attempts=int(raw.get("otp_max_attempts") or 5),
            project_root=project_root,
            broker_port=int(raw.get("broker_port") or 18090),
            log_max_lines=int(raw.get("log_max_lines") or 80),
            file_root=str(raw.get("file_root") or ""),
            file_max_mb=int(raw.get("file_max_mb") or 20),
            file_deny_patterns=tuple(raw.get("file_deny_patterns") or (
                "*.key", "*.pem", "*.pfx", "*.p12", "*secret*", "*password*", "*token*",
            )),
            allowed_hosts=tuple(raw.get("allowed_hosts") or ("127.0.0.1", "localhost")),
            config_path=config_path,
        )
        settings.ensure_data()
        return settings

    def ensure_data(self) -> None:
        """Ensure data.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
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
        """Db path.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        return self.data_dir / "webui.db"

    @property
    def server_secret(self) -> bytes:
        """Server secret.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        return (self.data_dir / "server_secret").read_bytes()

    @property
    def mailer_token_path(self) -> Path:
        """Mailer token path.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        return self.data_dir / "mailer_token"

    @property
    def mailer_token(self) -> str:
        """Mailer token.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        return self.mailer_token_path.read_text(encoding="ascii").strip()

    @property
    def session_seconds(self) -> int:
        """Session seconds.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        return self.session_days * 86400
