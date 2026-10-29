from __future__ import annotations

import argparse
import json
import logging
import os
import re
import secrets
import subprocess
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from email.message import EmailMessage
import smtplib
import ssl

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_BRIDGE = BASE_DIR.parent / "tools" / "email_secret_bridge.ps1"
DEFAULT_TOKEN = BASE_DIR / "data" / "mailer_token"
CODE_RE = re.compile(r"^\d{6}$")
LOG_PATH = BASE_DIR / "data" / "otp_mailer.log"
I18N_DIR = BASE_DIR / "static" / "i18n"
SUPPORTED_LANGS = {"zh", "en", "ja", "ko", "es", "fr", "de", "ru"}
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.FileHandler(LOG_PATH, encoding="utf-8"), logging.StreamHandler()],
)
logger = logging.getLogger("cyberbutler.otp_mailer")


def load_email_config(bridge: Path) -> dict:
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(bridge)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"DPAPI bridge failed: {completed.stderr[:200]}")
    return json.loads(completed.stdout)


def load_email_strings(lang: str) -> dict:
    code = lang if lang in SUPPORTED_LANGS else "zh"
    for candidate in (code, "zh"):
        path = I18N_DIR / f"{candidate}.json"
        try:
            return json.loads(path.read_text(encoding="utf-8")).get("strings", {})
        except (OSError, ValueError):
            continue
    return {}


def send_mail(config: dict, code: str, ttl: int, lang: str = "zh") -> None:
    strings = load_email_strings(lang)
    subject = strings.get("email.subject") or "Cyber-Butler"
    body = strings.get("email.body") or "{code}"
    minutes = max(1, ttl // 60)
    body = body.replace("{code}", code).replace("{minutes}", str(minutes))
    message = EmailMessage()
    message["From"] = config["smtp_from"]
    message["To"] = config["approval_to"]
    message["Subject"] = subject
    message.set_content(body)
    with smtplib.SMTP_SSL(
        config["smtp_host"], int(config["smtp_port"]), timeout=25,
        context=ssl.create_default_context(),
    ) as server:
        server.login(config["smtp_user"], config["smtp_pass"])
        server.send_message(message)


class Handler(BaseHTTPRequestHandler):
    server_version = "CyberButlerOtpMailer/1.0"
    token = ""
    bridge = DEFAULT_BRIDGE
    _hits: dict[str, deque[float]] = defaultdict(deque)

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self) -> bool:
        provided = self.headers.get("Authorization", "")
        expected = f"Bearer {self.token}"
        return secrets.compare_digest(provided, expected)

    def _rate_ok(self) -> bool:
        now = time.monotonic()
        bucket = self._hits["send"]
        while bucket and now - bucket[0] > 60:
            bucket.popleft()
        if len(bucket) >= 5:
            return False
        bucket.append(now)
        return True

    def do_GET(self) -> None:
        if self.path == "/health":
            self._json(200, {"ok": True})
        else:
            self._json(404, {"ok": False})

    def do_POST(self) -> None:
        if self.path != "/send-otp":
            self._json(404, {"ok": False})
            return
        if not self._auth():
            self._json(401, {"ok": False, "error": "unauthorized"})
            return
        if not self._rate_ok():
            self._json(429, {"ok": False, "error": "rate limited"})
            return
        try:
            length = min(int(self.headers.get("Content-Length", "0") or 0), 4096)
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            email = str(payload.get("email", "")).strip().lower()
            code = str(payload.get("code", "")).strip()
            ttl = int(payload.get("ttl", 300))
            lang = str(payload.get("lang", "zh"))
            if not CODE_RE.fullmatch(code):
                raise ValueError("invalid code")
            config = load_email_config(self.bridge)
            if email != str(config["approval_to"]).strip().lower():
                self._json(403, {"ok": False, "error": "recipient not allowed"})
                return
            send_mail(config, code, ttl, lang)
            logger.info("OTP mail sent to configured recipient")
            self._json(200, {"ok": True})
        except Exception as exc:
            logger.error("OTP mail failed: %s", exc)
            self._json(500, {"ok": False, "error": "send failed"})

    def log_message(self, fmt: str, *args) -> None:
        logger.info("http: " + fmt, *args)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--token-file", default=str(DEFAULT_TOKEN))
    parser.add_argument("--bridge", default=str(DEFAULT_BRIDGE))
    args = parser.parse_args()

    token_path = Path(args.token_file)
    if not token_path.exists():
        raise SystemExit(f"mailer token missing: {token_path}")
    Handler.token = token_path.read_text(encoding="ascii").strip()
    Handler.bridge = Path(args.bridge)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    logger.info("OTP mailer listening on %s:%s", args.host, args.port)
    server.serve_forever()


if __name__ == "__main__":
    main()
