#!/usr/bin/env python3
"""Verify update-manifest.json against the pinned RSA public key."""
from __future__ import annotations

import argparse
import base64
import hashlib
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

# Pinned trust anchor: never load a public key from the writable install tree.
PINNED_PUBLIC_KEY = """-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAtuW1dWa4D+wPrgx2O6jC
+ztZQL+k49um0ebR3PQ3KB3ii+zNoS5vD13NwRD93/iHh+Dmk2TM+6B8q3Rk5sXQ
1bQKE7Q356YLNgdFvbgkd2MkaVTmU8eOzhoHLZWqtIVuw/3WPD2ASartZlCx6NGM
wiYI4nnyVZajpqO7OXaYa/sx3yk7gWloO/GypdJqnfN8mfSC3CJSglEfYLxxT8PM
EGR770TTbNp1iOlnICTng41860Qxnoh6Ptz5sc64bJFnlBSHDHTi8CEQC/2DTzCd
Y1JegPN+BMaanUjNlHOzPawII3MG/ALnuunC3lSylPCACfQCJn1iEOAMRpO9z/6j
N9TgyENJur5luOTHU5w14lnB2zdSqH04okryWxclwOFd7SquPYjfzndH1GwxWSFU
+RA1b1Rg3dqwoHdya31YnTRvXIK6GwCO1JjPGgW9hVAUpPOKyq7z3xnKWMpvRF19
naZryLhO3nI9E0dAqvWCVflqsWO+ctv04HRV+ghPGfgrAgMBAAE=
-----END PUBLIC KEY-----"""


def _load_pinned_public_key(path: str = "") -> rsa.RSAPublicKey:
    """Load the compiled-in key; a supplied file must byte-match it."""
    raw = PINNED_PUBLIC_KEY.encode("utf-8")
    if path:
        supplied = Path(path).read_bytes().strip()
        if supplied != raw.strip():
            raise ValueError("supplied public key does not match the pinned trust anchor")
    key = serialization.load_pem_public_key(raw)
    if not isinstance(key, rsa.RSAPublicKey):
        raise ValueError("pinned key is not RSA")
    return key


def _revoked(manifest: Path, revoked_file: str) -> str | None:
    """Return a revocation reason matching the manifest hash, if any."""
    if not revoked_file:
        return None
    path = Path(revoked_file)
    if not path.is_file():
        return None
    digest = hashlib.sha256(manifest.read_bytes()).hexdigest().upper()
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if parts[0].strip().upper() == digest:
            return parts[1].strip() if len(parts) > 1 and parts[1].strip() else "no reason supplied"
    return None


def main() -> int:
    """Verify revocation first, then the RSA signature."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--pubkey", default="")
    parser.add_argument("--revoked-file", default="")
    parser.add_argument("--build-report", default="")
    parser.add_argument("--qa-report", default="")
    parser.add_argument("--proof", default="")
    parser.add_argument("--legacy", action="store_true")
    args = parser.parse_args()

    manifest = Path(args.manifest)
    reason = _revoked(manifest, args.revoked_file)
    if reason:
        print("REVOKED: " + reason)
        return 1

    if not (args.build_report and args.qa_report and args.proof):
        if not args.legacy:
            print("LEGACY VERIFY MODE: 使用 --legacy 才能验旧签名")
            return 1
        try:
            public_key = _load_pinned_public_key(args.pubkey)
            signature = base64.b64decode(Path(args.signature).read_text(encoding="ascii").strip())
            public_key.verify(signature, manifest.read_bytes(), padding.PKCS1v15(), hashes.SHA256())
        except (InvalidSignature, ValueError, OSError) as exc:
            print(f"INVALID {type(exc).__name__}: {exc}")
            return 1
        print("VALID (LEGACY)")
        return 0

    try:
        public_key = _load_pinned_public_key(args.pubkey)
        signature = base64.b64decode(Path(args.signature).read_text(encoding="ascii").strip())
        parts = [
            hashlib.sha256(manifest.read_bytes()).hexdigest().upper(),
            hashlib.sha256(Path(args.build_report).read_bytes()).hexdigest().upper(),
            hashlib.sha256(Path(args.qa_report).read_bytes()).hexdigest().upper(),
            hashlib.sha256(Path(args.proof).read_bytes()).hexdigest().upper(),
        ]
        payload = "|".join(parts).encode("utf-8")
        public_key.verify(signature, payload, padding.PKCS1v15(), hashes.SHA256())
    except (InvalidSignature, ValueError, OSError) as exc:
        print(f"INVALID {type(exc).__name__}: {exc}")
        return 1
    print("VALID")
    return 0


if __name__ == "__main__":
    sys.exit(main())
