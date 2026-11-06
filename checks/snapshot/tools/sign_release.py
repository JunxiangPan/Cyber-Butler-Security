#!/usr/bin/env python3
"""Sign update-manifest.json only after the release gate is satisfied.

v1.6.4 gate:
  * reads quality-manifest.json and recomputes every count;
  * re-renders FINAL_QA_REPORT.md from the manifest and compares bytes;
  * requires QUALITY_MANIFEST_SHA256 in both BUILD_REPORT and QA;
  * refuses any non-passed release item.

v1.6.3 and older keep the legacy four-file signature format. They are accepted
only in compatibility mode, with a warning, and only when the update manifest
declares a version older than 1.6.4.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from quality.run_quality_matrix import render_report  # noqa: E402

FINAL_QA = "FINAL_QA_REPORT.md"
PROOF = "ACCEPTANCE_PROOF.md"
BUILD = "BUILD_REPORT.md"
QUALITY = "quality-manifest.json"
QUALITY_HASH_LINE = re.compile(r"(?m)^QUALITY_MANIFEST_SHA256:\s*([0-9A-Fa-f]{64})\s*$")
FIXED_HEADING = "## FIXED_THIS_ROUND"
NOT_FIXED_HEADING = "## NOT_FIXED_THIS_ROUND"
NONCE_RE = re.compile(r"^[A-Za-z0-9._:-]{16,}$")
CHALLENGE_RE = re.compile(r"^[A-Za-z0-9._:-]{8,}$")


class SignGateError(RuntimeError):
    """Raised when a release-gate check refuses signing."""


def _read(path: Path) -> str:
    """Read a release report or raise SignGateError."""
    if not path.is_file():
        raise SignGateError(f"{path.name} is missing")
    return path.read_text(encoding="utf-8-sig")


def _version_tuple(version: str) -> tuple[int, int, int]:
    """Parse a dotted release version into a three-part tuple."""
    parts = re.findall(r"\d+", version)
    if not parts:
        raise SignGateError("release version is missing or malformed")
    values = [int(part) for part in parts[:3]]
    return tuple(values + [0] * (3 - len(values)))  # type: ignore[return-value]


def release_version(path: Path) -> str:
    """Read the release version from update-manifest.json."""
    if not path.is_file():
        raise SignGateError("update-manifest.json is missing")
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:
        raise SignGateError("update-manifest.json is not valid JSON") from exc
    version = str(data.get("version", "")).strip()
    if not version:
        raise SignGateError("update-manifest.json has no version")
    return version


def _recount(items: list[dict]) -> dict[str, int]:
    """Recompute status counts from manifest items."""
    return {
        "total": len(items),
        "passed": sum(1 for item in items if item.get("status") == "passed"),
        "failed": sum(1 for item in items if item.get("status") in {"failed", "error"}),
        "blocked": sum(1 for item in items if item.get("status") == "blocked"),
        "skipped_by_design": sum(1 for item in items if item.get("status") == "skipped-by-design"),
    }


def check_quality(root: Path) -> str:
    """Recompute a v1.6.4+ manifest and verify its report bindings."""
    quality_path = root / QUALITY
    if not quality_path.is_file():
        raise SignGateError("quality-manifest.json is required for v1.6.4 and newer")
    raw = quality_path.read_bytes()
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise SignGateError("quality-manifest.json is not valid JSON") from exc
    if data.get("schema") != "cbp-quality-manifest/v1":
        raise SignGateError("quality-manifest.json has an unknown schema")
    if data.get("profile") != "release":
        raise SignGateError("quality-manifest.json is not in release profile")
    items = data.get("items")
    if not isinstance(items, list) or len(items) != 26:
        raise SignGateError("quality-manifest.json must contain exactly 26 items")
    ids = [str(item.get("id", "")) for item in items]
    if len(set(ids)) != 26:
        raise SignGateError("quality-manifest.json has duplicate or empty item IDs")
    counts = _recount(items)
    if data.get("counts") != counts:
        raise SignGateError("quality-manifest.json counts do not match its items")
    if counts["failed"] or counts["blocked"] or counts["skipped_by_design"]:
        raise SignGateError("quality-manifest.json contains non-passed release items")
    if counts["passed"] != 26:
        raise SignGateError("quality-manifest.json does not contain 26 passed items")
    nonce = str(data.get("nonce", ""))
    if not NONCE_RE.fullmatch(nonce):
        raise SignGateError("quality-manifest.json Nonce failed validation")
    digest = hashlib.sha256(raw).hexdigest().upper()
    expected_report = render_report(data, digest)
    actual_report = (root / FINAL_QA).read_text(encoding="utf-8", errors="strict")
    if actual_report != expected_report:
        raise SignGateError("FINAL_QA_REPORT.md does not match the manifest re-render")
    for name in (BUILD, FINAL_QA):
        text = _read(root / name)
        matches = QUALITY_HASH_LINE.findall(text)
        if not matches:
            raise SignGateError(f"{name} has no QUALITY_MANIFEST_SHA256 seal")
        if {match.upper() for match in matches} != {digest}:
            raise SignGateError(f"{name} QUALITY_MANIFEST_SHA256 does not match {QUALITY}")
    return nonce


def check_legacy(root: Path) -> str:
    """Accept v1.6.3 and older only in compatibility mode, without text-PASS."""
    text = _read(root / FINAL_QA)
    counts: dict[str, int] = {}
    for label in ("Matrix", "Passed", "Failed", "Blocked"):
        match = re.search(rf"(?m)^-\s*{label}:\s*(\d+)\s*$", text)
        if not match:
            raise SignGateError(f"legacy FINAL_QA_REPORT.md is missing {label} count")
        counts[label.lower()] = int(match.group(1))
    if counts["matrix"] != 26:
        raise SignGateError("legacy FINAL_QA_REPORT.md is not the 26-item matrix")
    if counts["passed"] + counts["failed"] + counts["blocked"] != 26:
        raise SignGateError("legacy FINAL_QA_REPORT.md counts do not add up to 26")
    if counts["failed"] or counts["blocked"] or counts["passed"] != 26:
        raise SignGateError("legacy FINAL_QA_REPORT.md contains blocked/failed items")
    match = re.search(r"(?m)^-\s*Nonce:\s*(\S+)\s*$", text)
    if not match or not NONCE_RE.fullmatch(match.group(1)):
        raise SignGateError("legacy FINAL_QA_REPORT.md Nonce failed validation")
    return match.group(1)


def check_proof(root: Path) -> str:
    """Validate proof evidence without relying on a text PASS marker."""
    text = _read(root / PROOF)
    required = (
        "negative_403=True",
        "negative_token=True",
        "negative_path=True",
        "script_immutable=True",
    )
    for marker in required:
        if marker not in text:
            raise SignGateError("acceptance evidence missing: " + marker)
    match = re.search(r"(?m)^-\s*Nonce:\s*(\S+)\s*$", text)
    if not match or not NONCE_RE.fullmatch(match.group(1)):
        raise SignGateError("ACCEPTANCE_PROOF.md Nonce failed validation")
    starts = re.findall(r"Acceptance script SHA256 \(start\):\s*([0-9A-Fa-f]{64})", text)
    ends = re.findall(r"Acceptance script SHA256 \(end\):\s*([0-9A-Fa-f]{64})", text)
    if not starts or not ends or starts[-1].upper() != ends[-1].upper():
        raise SignGateError("acceptance script changed while running")
    return match.group(1)


def _coverage(text: str) -> None:
    """Require non-empty static-analysis coverage lines."""
    for tool in ("mypy", "pyright", "PSSA", "vulture"):
        if not re.search(rf"{tool}:\s*\d+/\d+", text, re.IGNORECASE):
            raise SignGateError("BUILD_REPORT Static Analysis Coverage missing or blank for " + tool)


def _section_lines(text: str, heading: str) -> list[str]:
    """Extract and validate a BUILD_REPORT section."""
    if heading not in text:
        raise SignGateError("BUILD_REPORT missing section " + heading)
    body = text.split(heading, 1)[1].split("\n## ", 1)[0]
    lines = [line.strip()[2:].strip() for line in body.splitlines() if line.strip().startswith("- ")]
    if len(lines) < 3 or any(len(line) < 10 for line in lines):
        raise SignGateError("BUILD_REPORT section has fewer than 3 substantive lines: " + heading)
    if not any(re.search(r"\.(py|ps1|json|md)\b|\d", line) for line in lines):
        raise SignGateError("BUILD_REPORT section has no concrete file or number: " + heading)
    return lines


def check_build(root: Path, expected_challenge: str) -> tuple[str, str]:
    """Validate BUILD_REPORT against the challenge and proof."""
    text = _read(root / BUILD)
    match = re.search(r"(?m)^ChallengeCode:\s*(\S+)\s*$", text)
    if not match or not CHALLENGE_RE.fullmatch(match.group(1)):
        raise SignGateError("BUILD_REPORT ChallengeCode missing or malformed")
    if match.group(1) != expected_challenge:
        raise SignGateError("BUILD_REPORT challenge does not match --expected-challenge")
    _coverage(text)
    _section_lines(text, FIXED_HEADING)
    _section_lines(text, NOT_FIXED_HEADING)
    proof_hash = re.search(r"PROOF_SHA256:\s*`?([0-9A-Fa-f]{64})", text)
    if not proof_hash:
        raise SignGateError("BUILD_REPORT.md has no PROOF_SHA256 seal")
    actual = hashlib.sha256((root / PROOF).read_bytes()).hexdigest().upper()
    if proof_hash.group(1).upper() != actual:
        raise SignGateError("PROOF_SHA256 does not match ACCEPTANCE_PROOF.md")
    return match.group(1), actual


def check_nonce_consistency(root: Path, expected_challenge: str, version: str) -> None:
    """Require the same nonce across QA, proof, and build report."""
    if _version_tuple(version) >= (1, 6, 4):
        qa_nonce = check_quality(root)
    else:
        print("WARNING: legacy v1.6.3 four-file signature compatibility mode", file=sys.stderr)
        qa_nonce = check_legacy(root)
    proof_nonce = check_proof(root)
    build = _read(root / BUILD)
    challenge = re.search(r"(?m)^ChallengeCode:\s*(\S+)\s*$", build)
    if not challenge:
        raise SignGateError("BUILD_REPORT ChallengeCode missing or malformed")
    if not (qa_nonce == proof_nonce == challenge.group(1) == expected_challenge):
        raise SignGateError("Nonce/ChallengeCode mismatch across FINAL_QA_REPORT, BUILD_REPORT and ACCEPTANCE_PROOF")


def require_gate(root: Path, expected_challenge: str, version: str = "1.6.4") -> None:
    """Run every gate before the private key is touched."""
    check_nonce_consistency(root, expected_challenge, version)
    check_build(root, expected_challenge)


def main() -> int:
    """Validate all release gates before signing."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--signature", default="")
    parser.add_argument("--expected-challenge", required=True)
    parser.add_argument("--build-report", required=True)
    parser.add_argument("--qa-report", required=True)
    parser.add_argument("--proof", required=True)
    args = parser.parse_args()

    manifest = Path(args.manifest)
    version = release_version(manifest)
    try:
        require_gate(ROOT, args.expected_challenge, version)
    except SignGateError as exc:
        raise SystemExit("REFUSING TO SIGN: " + str(exc))

    signature = Path(args.signature) if args.signature else manifest.with_suffix(manifest.suffix + ".sig")
    build_path = Path(args.build_report)
    qa_path = Path(args.qa_report)
    proof_path = Path(args.proof)
    for path in (manifest, build_path, qa_path, proof_path):
        if not path.is_file():
            raise SystemExit("REFUSING TO SIGN: signed input file is missing: " + str(path))
    sign_manifest(manifest, Path(args.key), signature, build_path, qa_path, proof_path)
    print(f"SIGNED {signature}")
    return 0


def build_signed_payload(manifest: Path, build: Path, qa: Path, proof: Path) -> bytes:
    """Build the exact four-file payload signed by the release key."""
    parts = [
        hashlib.sha256(manifest.read_bytes()).hexdigest().upper(),
        hashlib.sha256(build.read_bytes()).hexdigest().upper(),
        hashlib.sha256(qa.read_bytes()).hexdigest().upper(),
        hashlib.sha256(proof.read_bytes()).hexdigest().upper(),
    ]
    return "|".join(parts).encode("utf-8")


def sign_manifest(
    manifest: Path,
    key: Path,
    signature: Path,
    build: Path | None = None,
    qa: Path | None = None,
    proof: Path | None = None,
) -> None:
    """Sign a release only after every gate passes."""
    private_key = serialization.load_pem_private_key(key.read_bytes(), password=None)
    if not isinstance(private_key, rsa.RSAPrivateKey):
        raise ValueError("release key must be RSA")
    if build is None or qa is None or proof is None:
        raise ValueError("build, qa and proof paths are required")
    payload = build_signed_payload(manifest, build, qa, proof)
    sig = private_key.sign(payload, padding.PKCS1v15(), hashes.SHA256())
    signature.write_text(base64.b64encode(sig).decode("ascii"), encoding="ascii")


if __name__ == "__main__":
    raise SystemExit(main())
