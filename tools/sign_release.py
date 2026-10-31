#!/usr/bin/env python3
"""Sign update-manifest.json with the RSA-3072 release key (run as admin)."""

from __future__ import annotations

import argparse
import base64
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--signature", default="")
    args = parser.parse_args()

    manifest = Path(args.manifest)
    signature = Path(args.signature) if args.signature else manifest.with_suffix(manifest.suffix + ".sig")
    private_key = serialization.load_pem_private_key(Path(args.key).read_bytes(), password=None)
    data = manifest.read_bytes()
    sig = private_key.sign(data, padding.PKCS1v15(), hashes.SHA256())
    signature.write_text(base64.b64encode(sig).decode("ascii"), encoding="ascii")
    print(f"SIGNED {signature}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
