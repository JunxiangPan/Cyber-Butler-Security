#!/usr/bin/env python3
"""Send a test email by decrypting the DPAPI machine-scope email secret.

This helper exists because .NET SmtpClient's implicit-SSL handling on port 465
is unreliable; Python's smtplib.SMTP_SSL talks to 163's SSL endpoint directly.
It prints no secrets.
"""

from __future__ import annotations

import base64
import json
import smtplib
import ssl
import sys
from email.message import EmailMessage
from pathlib import Path

try:
    import win32crypt
except ImportError:
    print("win32crypt is not installed")
    raise SystemExit(2)

SECRET = Path(r"C:\ProgramData\CyberButler\email_secret.json")


def main() -> int:
    try:
        envelope = json.loads(SECRET.read_text(encoding="utf-8"))
        entropy = str(envelope.get("entropy") or "").encode("utf-8")
        cipher = base64.b64decode(envelope["ciphertext"])
        plain = None
        errors = []
        for flags in (0, 0x4):
            try:
                _description, candidate = win32crypt.CryptUnprotectData(cipher, entropy, None, None, flags)
                plain = candidate
                break
            except Exception as exc:
                errors.append(f"flags={flags}: {type(exc).__name__}: {exc}")
        if plain is None:
            raise RuntimeError("; ".join(errors))
        config = json.loads(plain.decode("utf-8"))
    except Exception as exc:
        print(f"secret read/decrypt failed: {type(exc).__name__}: {exc}")
        return 3

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
