#!/usr/bin/env python3
"""Verify update-manifest.json against the pinned RSA public key."""
from __future__ import annotations

import argparse
import base64
import zipfile
import hashlib
import json
import sys
from pathlib import Path
from typing import cast

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sign_release

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

# Pinned trust anchor: never load a public key from the writable install tree.
PINNED_PUBLIC_KEY = """-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAyZNflUHU0Iq6FRwCyrHI
ZM+k85xbAn4r/mq7Od/dzOsOMnKNb8Q7bQD/Y3QZnp7kQaoSY9jcgRUP8h42FALw
rp7hwNAZDs+r/tK3puJ3oiUvWc/bc9lb7ePkdS8m7Wc1t1Y/5XNphCicKSDLZwNs
7s7YqVZe3BI74ZlO9mT+heEelpSlSXLx32w59qdiP8LlXFx8pYAgthHpMdQmTHv2
o/tXnkMgcFvXA2OByx01WYRWEqt8mqdPnkbiidwduDyvca6HSjroTG0i8a/lJGD3
AGJ5KAi0ylgfG9v01PwVLurUlSjgy4IACLYYdFb6HAVc0MttxcHGpt0f6bh4p/bM
cyrtSgcDCRylm3k/fR8YaLwwnRmwwyDdtv8Svf0rBqWXDONB7A5BuZlcUD9T3sqz
Q7Y6fKNt+j5JWu+Tdm3ktdk7OMUFexQyLuIW5uqurFeaSLfSRwVcIKUkPYOYqusJ
gN4gZu7wm+PyzyFAFeQUAIDWedOiDL66cdfU7FV3/hAlAgMBAAE=
-----END PUBLIC KEY-----"""


MIN_ACCEPTED_VERSION = (1, 6, 4)
LEGACY_PINNED_MANIFEST_SHA256 = "4FD70FA524DC973D134B677E7F6B1300B2385000FB57E9ECEBDA8EC114F2207"
LEGACY_PINNED_SIGNATURE_SHA256 = "DCBC343077B450DFA258E985F398A8FAD71CC6FD8349547A4FA57E90C996A235"


def _legacy_pinned(manifest: Path, signature: Path) -> bool:
    """Return True only for the exact signed v1.6.3 compatibility asset."""
    try:
        return (
            hashlib.sha256(manifest.read_bytes()).hexdigest().upper() == LEGACY_PINNED_MANIFEST_SHA256
            and hashlib.sha256(signature.read_bytes()).hexdigest().upper() == LEGACY_PINNED_SIGNATURE_SHA256
        )
    except OSError:
        return False


def _zip_installer_sha256(package: Path) -> str | None:
    """Return the SHA256 of START-INSTALLER.exe inside a release ZIP."""
    try:
        with zipfile.ZipFile(package) as archive:
            return hashlib.sha256(archive.read("START-INSTALLER.exe")).hexdigest().upper()
    except (KeyError, OSError, zipfile.BadZipFile):
        return None


def _verify_package_manifest(package: Path, manifest: Path) -> str | None:
    """Check every manifest file against the release ZIP bytes."""
    try:
        data = json.loads(manifest.read_text(encoding="utf-8-sig"))
        with zipfile.ZipFile(package) as archive:
            names = {name for name in archive.namelist() if not name.endswith("/")}
            expected = {str(item["path"]): item for item in data["files"]}
            missing = sorted(set(expected) - names)
            if missing:
                return "package missing manifest entries: " + ",".join(missing[:3])
            for path, item in expected.items():
                payload = archive.read(path)
                if len(payload) != int(item["size"]):
                    return "package size mismatch: " + path
                if hashlib.sha256(payload).hexdigest().lower() != str(item["sha256"]).lower():
                    return "package hash mismatch: " + path
            unlisted = sorted(names - set(expected) - {"update-manifest.json"})
            if unlisted:
                return "package contains unlisted entries: " + ",".join(unlisted[:3])
        return None
    except (KeyError, ValueError, OSError, zipfile.BadZipFile) as exc:
        return "package manifest check failed: " + str(exc)


def _proof_installer_sha256(proof: Path) -> str | None:
    """Read the installer hash recorded by Run-Final-Acceptance.ps1."""
    import re
    match = re.search(r"(?m)^-\s*Installer SHA256:\s*([0-9A-Fa-f]{64})\s*$", proof.read_text(encoding="utf-8-sig"))
    return match.group(1).upper() if match else None


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
    parser.add_argument("--quality-manifest", default="")
    parser.add_argument("--legacy", action="store_true")
    parser.add_argument("--package", default="")
    args = parser.parse_args()

    manifest = Path(args.manifest)
    version = sign_release.release_version(manifest)
    version_tuple: tuple[int, int, int]
    try:
        version_tuple = cast(tuple[int, int, int], sign_release._version_tuple(version))
    except sign_release.SignGateError:
        version_tuple = cast(tuple[int, int, int], (1, 6, 3))
    reason = _revoked(manifest, args.revoked_file)
    if reason:
        print("REVOKED: " + reason)
        return 1

    pinned_legacy = _legacy_pinned(manifest, Path(args.signature))
    if version_tuple < MIN_ACCEPTED_VERSION and not args.legacy and not pinned_legacy:
        print("DOWNGRADE_REJECTED: version < 1.6.4; pass --legacy only for an audited old asset")
        return 1
    if args.package:
        expected_installer = _proof_installer_sha256(Path(args.proof))
        actual_installer = _zip_installer_sha256(Path(args.package))
        if expected_installer and actual_installer and expected_installer != actual_installer:
            print("INVALID: final package START-INSTALLER.exe does not match ACCEPTANCE_PROOF")
            return 1
        package_error = _verify_package_manifest(Path(args.package), manifest)
        if package_error:
            print("INVALID: " + package_error)
            return 1
    if not (args.build_report and args.qa_report and args.proof):
        if version_tuple >= MIN_ACCEPTED_VERSION:
            print("INVALID ValueError: v1.6.4 requires the four-file signature reports")
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
        if version_tuple >= (1, 6, 4):
            sign_release.check_quality(Path(args.qa_report).parent)
        else:
            print("WARNING: legacy v1.6.3 four-file signature format", file=sys.stderr)
        parts = [
            hashlib.sha256(manifest.read_bytes()).hexdigest().upper(),
            hashlib.sha256(Path(args.build_report).read_bytes()).hexdigest().upper(),
            hashlib.sha256(Path(args.qa_report).read_bytes()).hexdigest().upper(),
            hashlib.sha256(Path(args.proof).read_bytes()).hexdigest().upper(),
        ]
        payload = "|".join(parts).encode("utf-8")
        public_key.verify(signature, payload, padding.PKCS1v15(), hashes.SHA256())
    except (InvalidSignature, ValueError, OSError, sign_release.SignGateError) as exc:
        print(f"INVALID {type(exc).__name__}: {exc}")
        return 1
    if args.package:
        expected_installer = _proof_installer_sha256(Path(args.proof))
        actual_installer = _zip_installer_sha256(Path(args.package))
        if not expected_installer or not actual_installer:
            print("INVALID: package/installer hash missing from proof or ZIP")
            return 1
        if expected_installer != actual_installer:
            print("INVALID: final package START-INSTALLER.exe does not match ACCEPTANCE_PROOF")
            return 1
    print("VALID")
    return 0


if __name__ == "__main__":
    sys.exit(main())
