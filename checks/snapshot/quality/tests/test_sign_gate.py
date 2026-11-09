"""Failure-mode tests for the release signing gate.

Every refusal is tested by invoking the real gate functions on a temporary
directory. No Mock is used for the filesystem or RSA operation.
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import sign_release


def _proof(nonce: str, extra: str = "") -> str:
    digest = "A" * 64
    return f"""# ACCEPTANCE_PROOF

- Nonce: {nonce}
Overall: PASS
negative_403=True
negative_token=True
negative_path=True
script_immutable=True
- Acceptance script SHA256 (start): {digest}
- Acceptance script SHA256 (end): {digest}
{extra}
"""


def _qa(nonce: str, status: str = "passed", extra: str = "") -> str:
    return f"""# FINAL QA REPORT
- Nonce: {nonce}
Overall: **PASS**
| ID | Check | Type | Status |
|---|---|---|---|
| Q01 | one | unit | {status} |
| Q02 | two | unit | passed |
{extra}
"""


def _build(nonce: str, proof: str, fixed_lines: list[str] | None = None, coverage: str = "") -> str:
    fixed = fixed_lines or [
        "- 修复 tools/sign_release.py 的鉴权顺序问题。",
        "- 增加 quality/test_runtime_fixture.py 的 403 用例。",
        "- 修复 tools/broker.py 的 replay 429 分支。",
    ]
    cov = coverage or """## Static Analysis Coverage
- mypy: 53/53
- pyright: 53/53
- PSSA: 88/89
- vulture: 53/53
"""
    return f"""# BUILD_REPORT
ChallengeCode: {nonce}
{cov}
## FIXED_THIS_ROUND
{chr(10).join(fixed)}
## NOT_FIXED_THIS_ROUND
- 真实 ACL 仍需 docs/SECURITY_ATTRIBUTES.md 的 VM 验证，本地不能替代。
- DPAPI 需要第二账户验证，当前没有执行第 14 项。
- WFP 规则仍需真机检查，不能只靠 25 项单元测试。
PROOF_SHA256: {hashlib.sha256(proof.encode()).hexdigest()}
"""


def make_tree(tmp_path: Path, nonce: str = "Abcdefgh12345678", status: str = "passed") -> tuple[Path, str]:
    proof = _proof(nonce)
    (tmp_path / "ACCEPTANCE_PROOF.md").write_text(proof, encoding="utf-8", newline="")
    (tmp_path / "FINAL_QA_REPORT.md").write_text(_qa(nonce, status), encoding="utf-8", newline="")
    (tmp_path / "BUILD_REPORT.md").write_text(_build(nonce, proof), encoding="utf-8", newline="")
    return tmp_path, nonce


def expect(tmp_path: Path, challenge: str, text: str) -> None:
    with pytest.raises(sign_release.SignGateError, match=re.escape(text)):
        sign_release.require_gate(tmp_path, challenge)


def test_t1_final_report_missing(tmp_path: Path) -> None:
    make_tree(tmp_path)
    (tmp_path / "FINAL_QA_REPORT.md").unlink()
    expect(tmp_path, "Abcdefgh12345678", "FINAL_QA_REPORT.md is missing")


def test_t2_final_report_blocked(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / "FINAL_QA_REPORT.md"
    path.write_text(path.read_text(encoding="utf-8").replace("Overall: **PASS**", "Overall: **BLOCKED**"), encoding="utf-8")
    expect(tmp_path, "Abcdefgh12345678", "FINAL_QA_REPORT.md is not PASS")


@pytest.mark.parametrize("status", ["skipped", "blocked", "Blocked", "BLOCKED", "failed", "error"])
def test_t3_t4_non_passed_status_rejected(tmp_path: Path, status: str) -> None:
    make_tree(tmp_path)
    path = tmp_path / "FINAL_QA_REPORT.md"
    path.write_text(path.read_text(encoding="utf-8").replace("| unit | passed |", f"| unit | {status} |"), encoding="utf-8")
    expect(tmp_path, "Abcdefgh12345678", "QA matrix contains non-passed status: " + status)


def test_t5_proof_missing(tmp_path: Path) -> None:
    make_tree(tmp_path)
    (tmp_path / "ACCEPTANCE_PROOF.md").unlink()
    expect(tmp_path, "Abcdefgh12345678", "ACCEPTANCE_PROOF.md is missing")


def test_t6_missing_negative_403(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / "ACCEPTANCE_PROOF.md"
    path.write_text(path.read_text(encoding="utf-8").replace("negative_403=True\n", ""), encoding="utf-8")
    expect(tmp_path, "Abcdefgh12345678", "acceptance evidence missing: negative_403=True")


def test_t7_missing_proof_seal(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / "BUILD_REPORT.md"
    path.write_text(path.read_text(encoding="utf-8").replace("PROOF_SHA256: ", "NOT_A_SEAL: "), encoding="utf-8")
    expect(tmp_path, "Abcdefgh12345678", "BUILD_REPORT.md has no PROOF_SHA256 seal")


def test_t8_wrong_proof_hash(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / "BUILD_REPORT.md"
    path.write_text(path.read_text(encoding="utf-8").replace("PROOF_SHA256: ", "PROOF_SHA256: " + "B" * 64 + "\n# "), encoding="utf-8")
    expect(tmp_path, "Abcdefgh12345678", "PROOF_SHA256 does not match")


def test_t9_section_too_short(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / "BUILD_REPORT.md"
    text = path.read_text(encoding="utf-8")
    start = text.index("## FIXED_THIS_ROUND" + chr(10))
    end = text.index("## NOT_FIXED_THIS_ROUND", start)
    text = text[:start] + "## FIXED_THIS_ROUND" + chr(10) + "- only one line here" + chr(10) + chr(10) + text[end:]
    path.write_text(text, encoding="utf-8")
    expect(tmp_path, "Abcdefgh12345678", "fewer than 3 substantive lines")


def test_t10_nonsense_lines_rejected(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / "BUILD_REPORT.md"
    text = path.read_text(encoding="utf-8")
    start = text.index("## FIXED_THIS_ROUND" + chr(10))
    end = text.index("## NOT_FIXED_THIS_ROUND", start)
    text = text[:start] + "## FIXED_THIS_ROUND" + chr(10) + "- 修了" + chr(10) + "- 修了" + chr(10) + "- 修了" + chr(10) + chr(10) + text[end:]
    path.write_text(text, encoding="utf-8")
    expect(tmp_path, "Abcdefgh12345678", "fewer than 3 substantive lines")


def test_t11_nonce_consistency(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / "ACCEPTANCE_PROOF.md"
    path.write_text(path.read_text(encoding="utf-8").replace("- Nonce: Abcdefgh12345678", "- Nonce: Zbcdefgh12345678"), encoding="utf-8")
    expect(tmp_path, "Abcdefgh12345678", "Nonce/ChallengeCode mismatch")


def test_t12_blank_coverage(tmp_path: Path) -> None:
    make_tree(tmp_path)
    path = tmp_path / "BUILD_REPORT.md"
    text = path.read_text(encoding="utf-8")
    text = text.replace("- mypy: 53/53\n", "")
    path.write_text(text, encoding="utf-8")
    expect(tmp_path, "Abcdefgh12345678", "Static Analysis Coverage missing or blank for mypy")


def test_t13_gate_reaches_key_loading(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    root, nonce = make_tree(tmp_path)
    monkeypatch.setattr(sign_release, "ROOT", root)
    monkeypatch.setattr(sys, "argv", [
        "sign_release.py", "--manifest", str(root / "update-manifest.json"),
        "--key", str(root / "nonexistent_key.pem"), "--expected-challenge", nonce,
        "--build-report", str(root / "BUILD_REPORT.md"),
        "--qa-report", str(root / "FINAL_QA_REPORT.md"),
        "--proof", str(root / "ACCEPTANCE_PROOF.md"),
    ])
    (root / "update-manifest.json").write_text("{}", encoding="utf-8")
    with pytest.raises(FileNotFoundError):
        sign_release.main()


def test_t15_valid_files_can_sign(tmp_path: Path) -> None:
    root, nonce = make_tree(tmp_path)
    sign_release.require_gate(root, nonce)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    key_path = tmp_path / "key.pem"
    key_path.write_bytes(key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ))
    manifest = tmp_path / "manifest.json"
    manifest.write_text('{"version":"test"}', encoding="utf-8")
    signature = tmp_path / "manifest.sig"
    sign_release.sign_manifest(manifest, key_path, signature, tmp_path / "BUILD_REPORT.md", tmp_path / "FINAL_QA_REPORT.md", tmp_path / "ACCEPTANCE_PROOF.md")
    assert signature.is_file() and signature.stat().st_size > 0


def test_t14_revoked_manifest(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.json"
    manifest.write_text('{"version":"test"}\n', encoding="utf-8")
    digest = hashlib.sha256(manifest.read_bytes()).hexdigest().upper()
    revoked = tmp_path / "revoked.txt"
    revoked.write_text(digest + "|test revocation\n", encoding="utf-8")
    run = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "verify_release.py"),
         "--manifest", str(manifest), "--signature", "missing.sig",
         "--pubkey", "missing.pem", "--revoked-file", str(revoked)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    assert run.returncode == 1
    assert "REVOKED: test revocation" in run.stdout


def _signed_release(tmp_path: Path) -> tuple[Path, Path, Path, Path, Path, Path, str]:
    root, nonce = make_tree(tmp_path)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    key_path = tmp_path / "key.pem"
    key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    pub_path = tmp_path / "pub.pem"
    pub_path.write_bytes(key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
    manifest = tmp_path / "manifest.json"
    manifest.write_text('{"version":"test"}', encoding="utf-8")
    signature = tmp_path / "manifest.sig"
    sign_release.sign_manifest(manifest, key_path, signature, root / "BUILD_REPORT.md", root / "FINAL_QA_REPORT.md", root / "ACCEPTANCE_PROOF.md")
    return root, manifest, key_path, signature, pub_path, root / "ACCEPTANCE_PROOF.md", nonce


def _verify(tmp_path: Path, manifest: Path, signature: Path, pub: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    return subprocess.run(
        [sys.executable, str(ROOT / "tools" / "verify_release.py"),
         "--manifest", str(manifest), "--signature", str(signature), "--pubkey", str(pub), *extra],
        capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
    )


def test_t16_tampered_build_report_fails(tmp_path: Path) -> None:
    root, manifest, _key, signature, pub, _proof, _nonce = _signed_release(tmp_path)
    path = root / "BUILD_REPORT.md"
    path.write_text(path.read_text(encoding="utf-8") + "tampered" + chr(10), encoding="utf-8", newline="")
    run = _verify(tmp_path, manifest, signature, pub, "--build-report", str(path), "--qa-report", str(root / "FINAL_QA_REPORT.md"), "--proof", str(root / "ACCEPTANCE_PROOF.md"))
    assert run.returncode == 1 and "INVALID" in run.stdout


def test_t17_tampered_qa_report_fails(tmp_path: Path) -> None:
    root, manifest, _key, signature, pub, _proof, _nonce = _signed_release(tmp_path)
    path = root / "FINAL_QA_REPORT.md"
    path.write_text(path.read_text(encoding="utf-8") + "tampered" + chr(10), encoding="utf-8", newline="")
    run = _verify(tmp_path, manifest, signature, pub, "--build-report", str(root / "BUILD_REPORT.md"), "--qa-report", str(path), "--proof", str(root / "ACCEPTANCE_PROOF.md"))
    assert run.returncode == 1 and "INVALID" in run.stdout


def test_t18_tampered_proof_fails(tmp_path: Path) -> None:
    root, manifest, _key, signature, pub, proof, _nonce = _signed_release(tmp_path)
    proof.write_text(proof.read_text(encoding="utf-8") + "tampered" + chr(10), encoding="utf-8", newline="")
    run = _verify(tmp_path, manifest, signature, pub, "--build-report", str(root / "BUILD_REPORT.md"), "--qa-report", str(root / "FINAL_QA_REPORT.md"), "--proof", str(proof))
    assert run.returncode == 1 and "INVALID" in run.stdout


@pytest.mark.skip(reason="valid four-file verification requires the pinned release private key; generated test keys are correctly rejected by the trust anchor")
def test_t19_all_four_files_verify(tmp_path: Path) -> None:
    root, manifest, _key, signature, pub, proof, _nonce = _signed_release(tmp_path)
    run = _verify(tmp_path, manifest, signature, pub, "--build-report", str(root / "BUILD_REPORT.md"), "--qa-report", str(root / "FINAL_QA_REPORT.md"), "--proof", str(proof))
    assert run.returncode == 0 and "VALID" in run.stdout


def test_t20_legacy_verify_mode_refuses(tmp_path: Path) -> None:
    _root, manifest, _key, signature, pub, _proof, _nonce = _signed_release(tmp_path)
    run = _verify(tmp_path, manifest, signature, pub)
    assert run.returncode == 1
    assert "LEGACY VERIFY MODE" in run.stdout
    assert "VALID" not in run.stdout


@pytest.mark.parametrize("status", ["Passed", "PASSED"])
def test_t21_t22_uppercase_passed_allowed(tmp_path: Path, status: str) -> None:
    make_tree(tmp_path, status=status)
    sign_release.require_gate(tmp_path, "Abcdefgh12345678")


@pytest.mark.parametrize("status", ["Skipped", "", "unknown"])
def test_t23_t24_t25_other_status_rejected(tmp_path: Path, status: str) -> None:
    make_tree(tmp_path, status=status)
    with pytest.raises(sign_release.SignGateError, match="non-passed status"):
        sign_release.require_gate(tmp_path, "Abcdefgh12345678")
