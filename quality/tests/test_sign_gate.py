"""Release-gate behaviour after the v1.6.4 manifest migration.

This file replaces the old string/PASS-marker tests. The gate now consumes
quality-manifest.json; the dedicated adversarial cases live in
test_sign_gate_negative.py.
"""
from __future__ import annotations

import base64
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT))
import sign_release  # noqa: E402
from quality.run_quality_matrix import render_report  # noqa: E402

ITEMS = json.loads((ROOT / "quality" / "quality-items.json").read_text(encoding="utf-8"))["items"]
NONCE = "A-READY-SIGN-0001"


def _manifest(status: dict[str, str] | None = None) -> dict:
    rows = [{**item, "status": (status or {}).get(item["id"], "passed")} for item in ITEMS]
    return {"schema": "cbp-quality-manifest/v1", "version": "1.6.4", "nonce": NONCE, "profile": "release", "generated_at": "2026-11-06T00:00:00Z", "source": {"pytest": "pytest_exit=0"}, "items": rows, "counts": {"total": 26, "passed": sum(1 for r in rows if r["status"] == "passed"), "failed": 0, "blocked": sum(1 for r in rows if r["status"] == "blocked"), "skipped_by_design": 0}, "overall": "PASS"}


def _proof() -> str:
    digest = "A" * 64
    return f"""# ACCEPTANCE_PROOF
- Nonce: {NONCE}
negative_403=True
negative_token=True
negative_path=True
script_immutable=True
- Acceptance script SHA256 (start): {digest}
- Acceptance script SHA256 (end): {digest}
"""


def make_tree(tmp_path: Path) -> Path:
    data = _manifest()
    quality = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    (tmp_path / sign_release.QUALITY).write_bytes(quality.encode("utf-8"))
    digest = hashlib.sha256(quality.encode("utf-8")).hexdigest().upper()
    (tmp_path / sign_release.FINAL_QA).write_text(render_report(data, digest), encoding="utf-8")
    proof = _proof()
    (tmp_path / sign_release.PROOF).write_bytes(proof.encode("utf-8"))
    build = f"""# BUILD_REPORT
ChallengeCode: {NONCE}
QUALITY_MANIFEST_SHA256: {digest}
## Static Analysis Coverage
- mypy: 10/10
- pyright: 10/10
- PSSA: 10/10
- vulture: 10/10
## FIXED_THIS_ROUND
- 修复 tools/sign_release.py 的 manifest 复算逻辑。
- 修复 FINAL_QA_REPORT.md 的重渲染比对逻辑。
- 修复 quality-manifest.json 的 counts 校验。
## NOT_FIXED_THIS_ROUND
- 真实 ACL 仍需 VM 验证，见 docs/THREAT_MODEL.md。
- DPAPI 极端 I/O 分支仍未覆盖，见 Q16。
- WFP 仍是 audit-only，见 wfp-guard-status.json。
PROOF_SHA256: {hashlib.sha256(proof.encode()).hexdigest().upper()}
"""
    (tmp_path / sign_release.BUILD).write_text(build, encoding="utf-8")
    (tmp_path / "update-manifest.json").write_text('{"version":"1.6.4"}\n', encoding="utf-8")
    return tmp_path


def test_valid_manifest_passes_gate(tmp_path: Path) -> None:
    make_tree(tmp_path)
    sign_release.require_gate(tmp_path, NONCE, "1.6.4")


def test_missing_quality_manifest_rejected(tmp_path: Path) -> None:
    make_tree(tmp_path)
    (tmp_path / sign_release.QUALITY).unlink()
    with pytest.raises(sign_release.SignGateError, match="required for v1.6.4"):
        sign_release.require_gate(tmp_path, NONCE, "1.6.4")


def test_proof_missing(tmp_path: Path) -> None:
    make_tree(tmp_path)
    (tmp_path / sign_release.PROOF).unlink()
    with pytest.raises(sign_release.SignGateError, match="ACCEPTANCE_PROOF.md is missing"):
        sign_release.require_gate(tmp_path, NONCE, "1.6.4")


def test_proof_marker_missing(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / sign_release.PROOF
    path.write_text(path.read_text(encoding="utf-8").replace("negative_403=True\n", ""), encoding="utf-8")
    with pytest.raises(sign_release.SignGateError, match="negative_403=True"):
        sign_release.require_gate(tmp_path, NONCE, "1.6.4")


def test_build_proof_hash_mismatch(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / sign_release.BUILD
    path.write_text(path.read_text(encoding="utf-8").replace("PROOF_SHA256:", "PROOF_SHA256: 0"), encoding="utf-8")
    with pytest.raises(sign_release.SignGateError, match="PROOF_SHA256"):
        sign_release.require_gate(tmp_path, NONCE, "1.6.4")


def test_coverage_missing(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / sign_release.BUILD
    path.write_text(path.read_text(encoding="utf-8").replace("- mypy: 10/10\n", ""), encoding="utf-8")
    with pytest.raises(sign_release.SignGateError, match="mypy"):
        sign_release.require_gate(tmp_path, NONCE, "1.6.4")


def test_nonce_mismatch(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / sign_release.PROOF
    path.write_text(path.read_text(encoding="utf-8").replace(NONCE, "A-READY-SIGN-0002"), encoding="utf-8")
    with pytest.raises(sign_release.SignGateError, match="Nonce/ChallengeCode mismatch"):
        sign_release.require_gate(tmp_path, NONCE, "1.6.4")


def test_valid_signed_four_files(tmp_path: Path) -> None:
    root = make_tree(tmp_path)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    key_path = tmp_path / "key.pem"
    key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    manifest = tmp_path / "update-manifest.json"
    signature = tmp_path / "manifest.sig"
    sign_release.sign_manifest(manifest, key_path, signature, root / sign_release.BUILD, root / sign_release.FINAL_QA, root / sign_release.PROOF)
    payload = sign_release.build_signed_payload(manifest, root / sign_release.BUILD, root / sign_release.FINAL_QA, root / sign_release.PROOF)
    signature_bytes = base64.b64decode(signature.read_text(encoding="ascii"))
    key.public_key().verify(signature_bytes, payload, padding.PKCS1v15(), hashes.SHA256())
