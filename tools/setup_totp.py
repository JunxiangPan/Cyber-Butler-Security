#!/usr/bin/env python3
"""Create a TOTP secret, QR code and three recovery codes."""

from __future__ import annotations

import hashlib
import json
import secrets
import subprocess
from pathlib import Path

import pyotp
import qrcode
import win32crypt

ROOT = Path(r"YOUR_PROJECT_PATH")
SECRET_FILE = ROOT / "tools" / "totp_secret.dpapi"
RECOVERY_STORE = ROOT / "tools" / "totp_recovery.json"
QR_PATH = Path(r"YOUR_USER_PATH\Desktop\苏瑾言TOTP.png")
RECOVERY_TXT = Path(r"YOUR_USER_PATH\Desktop\苏瑾言TOTP恢复码.txt")
ISSUER = "苏瑾言"
ACCOUNT = "YOUR_QQ_ID"


def main() -> int:
    secret = pyotp.random_base32()
    uri = pyotp.TOTP(secret).provisioning_uri(name=ACCOUNT, issuer_name=ISSUER)
    qr = qrcode.QRCode(box_size=10, border=4)
    qr.add_data(uri)
    qr.make(fit=True)
    qr.make_image(fill_color="black", back_color="white").save(QR_PATH)

    # 0x4 is CRYPTPROTECT_LOCAL_MACHINE: the Broker (SYSTEM) can decrypt it,
    # but any local principal that can read the wrapped file can also decrypt
    # it. The vault ACL is the effective boundary; this is not user binding.
    encrypted = win32crypt.CryptProtectData(
        secret.encode("utf-8"), "AstrBot TOTP", None, None, None, 0x4
    )
    SECRET_FILE.write_bytes(encrypted)

    codes = ["".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(8)) for _ in range(3)]
    hashes = [hashlib.sha256(code.encode("utf-8")).hexdigest() for code in codes]
    RECOVERY_STORE.write_text(
        json.dumps({"sha256": hashes, "used": []}, ensure_ascii=True, indent=2),
        encoding="utf-8",
    )
    RECOVERY_TXT.write_text(
        "苏瑾言 TOTP 一次性恢复码（每码仅可用一次，手机丢失时使用）\n\n"
        + "\n".join(f"{i + 1}. {code}" for i, code in enumerate(codes))
        + "\n",
        encoding="utf-8",
    )
    # The broker runs as SYSTEM; the QR/recovery text belong to YOUR_USER_NAME.
    subprocess.run(
        ["icacls", str(SECRET_FILE), "/inheritance:r", "/grant:r", "SYSTEM:(F)", "*S-1-5-32-544:(F)"],
        check=False,
        capture_output=True,
    )
    subprocess.run(
        ["icacls", str(RECOVERY_STORE), "/inheritance:r", "/grant:r", "SYSTEM:(F)", "*S-1-5-32-544:(F)"],
        check=False,
        capture_output=True,
    )
    print("TOTP_QR_SAVED", QR_PATH)
    print("TOTP_RECOVERY_SAVED", RECOVERY_TXT)
    print("TOTP_SECRET_SAVED", SECRET_FILE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
