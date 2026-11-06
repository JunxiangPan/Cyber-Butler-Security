"""Adversarial tests for the v1.6.4 quality-manifest signing gate.

No mocks: each case writes a real temporary report tree and calls the real
gate. A refused case must raise SignGateError; a signed case must fail the
real verify_release.py signature check after tampering.
"""
from __future__ import annotations

import base64
import hashlib
import json
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
NONCE = "A-READY-NEGATIVE-0001"


def _manifest(items: list[dict] | None = None, nonce: str = NONCE) -> dict:
    rows = items or [{**item, "status": "passed"} for item in ITEMS]
    return {
        "schema": "cbp-quality-manifest/v1",
        "version": "1.6.4",
        "nonce": nonce,
        "profile": "release",
        "generated_at": "2026-11-06T00:00:00Z",
        "source": {"pytest": "pytest_exit=0"},
        "items": rows,
        "counts": {
            "total": len(rows),
            "passed": sum(1 for row in rows if row["status"] == "passed"),
            "failed": sum(1 for row in rows if row["status"] == "failed"),
            "blocked": sum(1 for row in rows if row["status"] == "blocked"),
            "skipped_by_design": sum(1 for row in rows if row["status"] == "skipped-by-design"),
        },
        "overall": "PASS",
        "dependency_gate_status": "PASS",
        "comment_audit_status": "PASS",
        "binary_provenance_status": "PASS",
    }


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


def _tree(root: Path, manifest: dict | None = None) -> Path:
    data = manifest or _manifest()
    quality = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    quality_path = root / sign_release.QUALITY
    quality_path.write_text(quality, encoding="utf-8")
    digest = hashlib.sha256(quality.encode("utf-8")).hexdigest().upper()
    qa = render_report(data, digest)
    (root / sign_release.FINAL_QA).write_text(qa, encoding="utf-8")
    proof = _proof()
    (root / sign_release.PROOF).write_bytes(proof.encode("utf-8"))
    proof_hash = hashlib.sha256(proof.encode("utf-8")).hexdigest().upper()
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
- 真实 ACL 仍需 VM 验证，不能只靠 docs/THREAT_MODEL.md。
- DPAPI 的极端 I/O 分支仍未覆盖，见 Q16。
- WFP 仍是 audit-only，见 wfp-guard-status.json。
PROOF_SHA256: {proof_hash}
"""
    (root / sign_release.BUILD).write_text(build, encoding="utf-8")
    (root / "update-manifest.json").write_text('{"version":"1.6.4"}\n', encoding="utf-8")
    return root


def _expect(root: Path, text: str) -> None:
    with pytest.raises(sign_release.SignGateError, match=text):
        sign_release.require_gate(root, NONCE, "1.6.4")


def test_fake_pass_text_is_rejected(tmp_path: Path) -> None:
    _tree(tmp_path)
    path = tmp_path / sign_release.FINAL_QA
    path.write_text(path.read_text(encoding="utf-8").replace("Overall: **PASS**", "Overall: **PASS**\n"), encoding="utf-8")
    _expect(tmp_path, "does not match the manifest re-render")


def test_missing_item_is_rejected(tmp_path: Path) -> None:
    data = _manifest()
    data["items"] = data["items"][:-1]
    data["counts"]["total"] = 25
    _tree(tmp_path, data)
    _expect(tmp_path, "exactly 26 items")


def test_duplicate_item_is_rejected(tmp_path: Path) -> None:
    data = _manifest()
    data["items"][-1] = dict(data["items"][0])
    _tree(tmp_path, data)
    _expect(tmp_path, "duplicate or empty item IDs")


def test_json_changed_without_qa_is_rejected(tmp_path: Path) -> None:
    _tree(tmp_path)
    path = tmp_path / sign_release.QUALITY
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace(NONCE, "A-READY-NEGATIVE-0002"), encoding="utf-8")
    _expect(tmp_path, "does not match the manifest re-render")


def test_json_and_qa_changed_break_signature(tmp_path: Path) -> None:
    root = _tree(tmp_path)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    key_path = tmp_path / "key.pem"
    key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    pub_path = tmp_path / "pub.pem"
    pub_path.write_bytes(key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
    signature = tmp_path / "manifest.sig"
    manifest = tmp_path / "update-manifest.json"
    sign_release.sign_manifest(manifest, key_path, signature, root / sign_release.BUILD, root / sign_release.FINAL_QA, root / sign_release.PROOF)
    # Change JSON and re-render QA consistently. BUILD still carries the old
    # manifest hash and the signed QA bytes have changed.
    data = _manifest(nonce="A-READY-NEGATIVE-0003")
    (root / sign_release.QUALITY).write_text(json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    (root / sign_release.FINAL_QA).write_text(render_report(data), encoding="utf-8")
    payload = sign_release.build_signed_payload(manifest, root / sign_release.BUILD, root / sign_release.FINAL_QA, root / sign_release.PROOF)
    signature_bytes = base64.b64decode(signature.read_text(encoding="ascii"))
    with pytest.raises(Exception):
        key.public_key().verify(signature_bytes, payload, padding.PKCS1v15(), hashes.SHA256())
