#!/usr/bin/env python3
"""SMTP/IMAP approval channel for the TOTP broker.

The broker runs as SYSTEM. Configuration is read through the DPAPI bridge,
never from a plaintext file. This module contains the transport and parsing
primitives; the broker integration lives in broker.py.
"""

from __future__ import annotations

import html
import imaplib
import json
import re
import smtplib
import ssl
import subprocess
from email import message_from_bytes, policy
from email.message import EmailMessage
from email.utils import parseaddr
from pathlib import Path

BRIDGE = Path(r"D:\qq苏瑾言大肥鱼\public-release\tools\email_secret_bridge.ps1")
APPROVE_RE = re.compile(r"^APPROVE\s+#([0-9A-Fa-f]{4,8})\s+TOTP\s*[:=]?\s*\+?(\d{6})\s*$")


class EmailConfigError(RuntimeError):
    pass


def load_config() -> dict:
    """Read the machine-DPAPI encrypted config through the PowerShell bridge."""
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(BRIDGE)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    if completed.returncode != 0:
        raise EmailConfigError(f"bridge failed: {completed.stderr[:200]}")
    try:
        config = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise EmailConfigError(f"bridge returned invalid json: {exc}") from exc
    required = ("smtp_host", "smtp_port", "smtp_user", "smtp_pass", "smtp_from",
                "approval_to", "imap_host", "imap_port", "imap_user", "imap_pass",
                "allowed_sender")
    missing = [key for key in required if not config.get(key)]
    if missing:
        raise EmailConfigError("missing config keys: " + ", ".join(missing))
    return config


def parse_approval_line(text: str) -> tuple[str, str] | None:
    """Return (challenge, totp) from the first non-empty line, or None."""
    text = str(text or "")
    for marker in ("------------------ 原始邮件", "-----原始邮件-----", "发件人:", "From:"):
        index = text.find(marker)
        if index > 0:
            text = text[:index]
            break
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        match = APPROVE_RE.match(line)
        if not match:
            return None
        return match.group(1).upper(), match.group(2)
    return None


def sender_allowed(from_header: str, allowed_sender: str) -> bool:
    _name, address = parseaddr(str(from_header or ""))
    return bool(address) and address.strip().lower() == str(allowed_sender).strip().lower()


def send_email(config: dict, subject: str, body: str) -> None:
    message = EmailMessage()
    message["From"] = config["smtp_from"]
    message["To"] = config["approval_to"]
    message["Subject"] = subject
    message.set_content(body)
    with smtplib.SMTP_SSL(
        config["smtp_host"],
        int(config["smtp_port"]),
        timeout=25,
        context=ssl.create_default_context(),
    ) as server:
        server.login(config["smtp_user"], config["smtp_pass"])
        server.send_message(message)


def _folders(mailbox):
    folders = ["INBOX"]
    for name in ("Sent", "&XfJT0ZAB-", "Sent Messages", "Sent Items", "&V4NXPpCuTvY-", "已发送", "已发送邮件"):
        try:
            typ, _ = mailbox.select(name)
            if typ == "OK":
                folders.append(name)
        except Exception:
            continue
    return folders


def _message_text(message) -> str:
    body = message.get_body(preferencelist=("plain", "html"))
    if body is None:
        return ""
    try:
        text = body.get_content()
    except Exception:
        return ""
    if body.get_content_type() == "text/html":
        text = re.sub(r"<[^>]+>", "\n", str(text))
        text = html.unescape(text)
    return str(text)
def poll_once(config: dict, expected_challenge: str = "") -> tuple[str, str, str] | None:
    """Read the newest approval reply from INBOX or Sent.

    The broker sends approval mail from/to the same mailbox, so 163 may store
    the owner's reply in Sent rather than INBOX. Only APPROVE lines are
    considered; quoted history is ignored by the first-line/fallback parser.
    """
    with imaplib.IMAP4_SSL(
        config["imap_host"],
        int(config["imap_port"]),
        ssl_context=ssl.create_default_context(),
    ) as mailbox:
        mailbox.login(config["imap_user"], config["imap_pass"])
        try:
            mailbox.xatom("ID", '("name" "CyberButler" "version" "1.3.2" "vendor" "local")')
        except Exception:
            pass
        for folder in _folders(mailbox):
            typ, _ = mailbox.select(folder)
            if typ != "OK":
                continue
            typ, data = mailbox.search(None, "ALL")
            if typ != "OK" or not data or not data[0]:
                continue
            for num in reversed(data[0].split()[-15:]):
                typ, fetched = mailbox.fetch(num, "(RFC822)")
                if typ != "OK" or not fetched:
                    continue
                message = message_from_bytes(fetched[0][1], policy=policy.default)
                text = _message_text(message)
                parsed = parse_approval_line(text)
                if not parsed:
                    continue
                if expected_challenge and parsed[0].upper() != str(expected_challenge).upper():
                    continue
                from_header = str(message.get("From", ""))
                if not sender_allowed(from_header, config["allowed_sender"]):
                    continue
                mailbox.store(num, "+FLAGS", "\Seen")
                return from_header, parsed[0], parsed[1]
    return None
