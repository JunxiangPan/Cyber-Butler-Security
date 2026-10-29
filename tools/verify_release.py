#!/usr/bin/env python3
"""Verify update-manifest.json against the pinned RSA public key."""

from __future__ import annotations

import argparse
import base64
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--pubkey", required=True)
    args = parser.parse_args()

    try:
        public_key = serialization.load_pem_public_key(Path(args.pubkey).read_bytes())
        signature = base64.b64decode(Path(args.signature).read_text(encoding="ascii").strip())
        public_key.verify(
            signature,
            Path(args.manifest).read_bytes(),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
    except (InvalidSignature, ValueError, OSError) as exc:
        print(f"INVALID {type(exc).__name__}: {exc}")
        return 1
    print("VALID")
    return 0


if __name__ == "__main__":
    sys.exit(main())
