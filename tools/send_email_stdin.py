#!/usr/bin/env python3
"""Send a test email from JSON supplied on stdin (no secret on disk/argv)."""

from __future__ import annotations

import json
import smtplib
import ssl
import sys
from email.message import EmailMessage


def main() -> int:
    try:
        config = json.loads(sys.stdin.read())
    except Exception as exc:
        print(f"invalid stdin json: {type(exc).__name__}: {exc}")
        return 2
    try:
        message = EmailMessage()
        message["From"] = config["smtp_from"]
        message["To"] = config["approval_to"]
        message["Subject"] = "[Cyber-Butler] SMTP/IMAP test"
        message.set_content(
            "Cyber-Butler email approval test.\n\n"
            "If you can read this, SMTP is configured.\n"
            "Do not reply to this message; the broker only reads approval replies."
        )
        with smtplib.SMTP_SSL(
            config["smtp_host"],
            int(config["smtp_port"]),
            timeout=25,
            context=ssl.create_default_context(),
        ) as server:
            server.login(config["smtp_user"], config["smtp_pass"])
            server.send_message(message)
        print("SENT")
        return 0
    except Exception as exc:
        print(f"send failed: {type(exc).__name__}: {exc}")
        return 4


if __name__ == "__main__":
    sys.exit(main())
