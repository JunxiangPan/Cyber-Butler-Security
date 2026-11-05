#!/usr/bin/env python3
"""Sign update-manifest.json only after the release gate is satisfied.

The gate is deliberately separate from the RSA operation so each rejection can
be tested without a private key. All checks run before the key is loaded.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import re
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

ROOT = Path(__file__).resolve().parents[1]
FINAL_QA = "FINAL_QA_REPORT.md"
PROOF = "ACCEPTANCE_PROOF.md"
BUILD = "BUILD_REPORT.md"
FIXED_HEADING = "## FIXED_THIS_ROUND"
NOT_FIXED_HEADING = "## NOT_FIXED_THIS_ROUND"
NONCE_RE = re.compile(r"^[A-Za-z0-9]{16,}$")
CHALLENGE_RE = re.compile(r"^[A-Za-z0-9._:-]{8,}$")


class SignGateError(RuntimeError):
    """Raised when a release-gate check refuses signing."""


def _read(path: Path) -> str:
    """Read a report or raise a gate error when absent."""
    if not path.is_file():
        raise SignGateError(f"{path.name} is missing")
    return path.read_text(encoding="utf-8-sig")


def _overall_pass(text: str, name: str) -> None:
    """Require an explicit PASS marker in a report."""
    if "Overall: **PASS**" not in text and "Overall: PASS" not in text:
        raise SignGateError(f"{name} is not PASS")


def _qa_statuses(text: str) -> list[str]:
    """Extract the status column from the four-column QA table."""
    statuses: list[str] = []
    for line in text.splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 4:
            continue
        if cells[0].lower() in {"id", "---"} or cells[1].lower() == "check":
            continue
        if set(cells[0]) <= {"-", ":"}:
            continue
        statuses.append(cells[-1])
    return statuses


def check_quality(root: Path) -> str:
    """Validate the 25-item report and return its Nonce."""
    text = _read(root / FINAL_QA)
    _overall_pass(text, FINAL_QA)
    statuses = _qa_statuses(text)
    bad = [status for status in statuses if status.casefold() not in {"passed", "pass"}]
    if bad:
        raise SignGateError("QA matrix contains non-passed status: " + ",".join(sorted(set(bad))))
    match = re.search(r"(?m)^-\s*Nonce:\s*(\S+)\s*$", text)
    if not match or not NONCE_RE.fullmatch(match.group(1)):
        raise SignGateError("FINAL_QA_REPORT.md Nonce failed validation")
    return match.group(1)


def check_proof(root: Path) -> str:
    """Validate the acceptance proof and return its Nonce."""
    text = _read(root / PROOF)
    _overall_pass(text, PROOF)
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
    """Require the four static-analysis coverage counters."""
    for tool in ("mypy", "pyright", "PSSA", "vulture"):
        if not re.search(rf"{tool}:\s*\d+/\d+", text, re.IGNORECASE):
            raise SignGateError("BUILD_REPORT Static Analysis Coverage missing or blank for " + tool)


def _section_lines(text: str, heading: str) -> list[str]:
    """Validate one mandatory BUILD_REPORT section."""
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
    """Validate BUILD_REPORT and return (challenge, actual proof hash)."""
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


def check_nonce_consistency(root: Path, expected_challenge: str) -> None:
    """Require all three nonce/challenge fields and the human input to agree."""
    qa_nonce = check_quality(root)
    proof_nonce = check_proof(root)
    build = _read(root / BUILD)
    challenge = re.search(r"(?m)^ChallengeCode:\s*(\S+)\s*$", build)
    if not challenge:
        raise SignGateError("BUILD_REPORT ChallengeCode missing or malformed")
    if not (qa_nonce == proof_nonce == challenge.group(1) == expected_challenge):
        raise SignGateError("Nonce/ChallengeCode mismatch across FINAL_QA_REPORT, BUILD_REPORT and ACCEPTANCE_PROOF")


def require_gate(root: Path, expected_challenge: str) -> None:
    """Run every gate before the private key is touched."""
    check_nonce_consistency(root, expected_challenge)
    check_build(root, expected_challenge)


def main() -> int:
    """Run the gate, then sign one manifest with an RSA key."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--signature", default="")
    parser.add_argument("--expected-challenge", required=True)
    parser.add_argument("--build-report", required=True)
    parser.add_argument("--qa-report", required=True)
    parser.add_argument("--proof", required=True)
    args = parser.parse_args()

    try:
        require_gate(ROOT, args.expected_challenge)
    except SignGateError as exc:
        raise SystemExit("REFUSING TO SIGN: " + str(exc))

    manifest = Path(args.manifest)
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
    """Hash four files and concatenate them in a fixed order."""
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
    """Sign the four-file payload, or the legacy manifest in fallback mode."""
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
