import hashlib
import json
import secrets
import sys
from pathlib import Path


def hash_dashboard_password(raw_password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", raw_password.encode("utf-8"), bytes.fromhex(salt), 600_000
    ).hex()
    return f"pbkdf2_sha256$600000${salt}${digest}"


def hash_md5_dashboard_password(raw_password: str) -> str:
    return hashlib.md5(raw_password.encode("utf-8")).hexdigest()


def main() -> int:
    if len(sys.argv) != 3:
        return 2
    root = Path(sys.argv[1])
    password = sys.argv[2]
    config_path = root / "AstrBot" / "data" / "cmd_config.json"
    config = {}
    if config_path.is_file():
        config = json.loads(config_path.read_text(encoding="utf-8-sig"))
    dashboard = config.setdefault("dashboard", {})
    dashboard["username"] = str(dashboard.get("username") or "astrbot")
    dashboard["pbkdf2_password"] = hash_dashboard_password(password)
    dashboard["password"] = hash_md5_dashboard_password(password)
    dashboard["password_storage_upgraded"] = True
    dashboard["password_change_required"] = True
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
    marker = root / "AstrBot" / "data" / ".cbs-dashboard-password-configured"
    marker.write_text("configured", encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
