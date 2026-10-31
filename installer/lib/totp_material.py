#!/usr/bin/env python3
"""Generate TOTP secret (DPAPI machine scope), QR image, and recovery codes.

This helper prints enrollment material exactly once so the installer can show
the Base32 secret, otpauth URI, and recovery codes to the operator. The
PowerShell installer applies the vault ACL after this process exits; it must not
write those values to the journal or install report.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import secrets
import sys
from pathlib import Path

import pyotp
import qrcode


def recovery_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(8))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vault", required=True)
    parser.add_argument("--secret", required=True)
    parser.add_argument("--recovery", required=True)
    parser.add_argument("--qr", required=True)
    parser.add_argument("--issuer", default="Cyber-Butler")
    parser.add_argument("--account", default="owner")
    args = parser.parse_args()

    vault = Path(args.vault)
    secret_path = Path(args.secret)
    recovery_path = Path(args.recovery)
    qr_path = Path(args.qr)
    vault.mkdir(parents=True, exist_ok=True)

    secret = pyotp.random_base32()
    uri = pyotp.TOTP(secret).provisioning_uri(name=args.account, issuer_name=args.issuer)
    qr = qrcode.QRCode(box_size=10, border=4)
    qr.add_data(uri)
    qr.make(fit=True)
    qr.make_image(fill_color="black", back_color="white").save(qr_path)

    try:
        import win32crypt
    except ImportError as exc:
        print(f"win32crypt is required: {exc}", file=sys.stderr)
        return 2
    encrypted = win32crypt.CryptProtectData(
        secret.encode("utf-8"), "Cyber-Butler TOTP", None, None, None, 0x4
    )
    secret_path.write_bytes(encrypted)

    codes = [recovery_code() for _ in range(3)]
    hashes = [hashlib.sha256(code.encode("utf-8")).hexdigest() for code in codes]
    recovery_path.write_text(
        "Cyber-Butler TOTP recovery codes (one use each)\n\n"
        + "\n".join(f"{i + 1}. {code}" for i, code in enumerate(codes))
        + "\n",
        encoding="utf-8",
    )
    # The recovery-hash store is separate so a printed code is not the stored secret.
    recovery_hashes = recovery_path.with_name("recovery_hashes.json")
    recovery_hashes.write_text(
        json.dumps({"sha256": hashes, "used": []}, ensure_ascii=True, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"TOTP_SECRET={secret}")
    print(f"TOTP_URI={uri}")
    for index, code in enumerate(codes, 1):
        print(f"TOTP_RECOVERY_{index}={code}")
    print("TOTP_MATERIAL_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
