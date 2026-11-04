#!/usr/bin/env python3
"""Sign update-manifest.json with the RSA-3072 release key (run as admin)."""

from __future__ import annotations

import argparse
import base64
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def _require_quality_gate() -> None:
    report = Path(__file__).resolve().parents[1] / "FINAL_QA_REPORT.md"
    if not report.is_file():
        raise SystemExit("REFUSING TO SIGN: FINAL_QA_REPORT.md is missing")
    text = report.read_text(encoding="utf-8")
    if "Overall: **PASS**" not in text and "Overall: PASS" not in text:
        raise SystemExit("REFUSING TO SIGN: FINAL_QA_REPORT.md is not PASS")
    if "| blocked |" in text or "| failed |" in text or "| error |" in text:
        raise SystemExit("REFUSING TO SIGN: QA matrix contains blocked/failed items")


def main() -> int:
    _require_quality_gate()
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
