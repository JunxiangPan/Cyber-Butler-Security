"""Real assertions for release tooling currently marked as security_core."""
from __future__ import annotations

import hashlib
import json
import sys
import types
import zipfile
from pathlib import Path

import pytest

import verify_release
import sanitize_for_release
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "installer" / "lib"))
import totp_material


def test_zip_installer_hash_and_missing(tmp_path: Path) -> None:
    package = tmp_path / "p.zip"
    with zipfile.ZipFile(package, "w") as archive:
        archive.writestr("START-INSTALLER.exe", b"launcher")
    assert verify_release._zip_installer_sha256(package) == hashlib.sha256(b"launcher").hexdigest().upper()
    assert verify_release._zip_installer_sha256(tmp_path / "missing.zip") is None


def test_package_manifest_roundtrip_and_mismatch(tmp_path: Path) -> None:
    package = tmp_path / "p.zip"
    payload = b"hello"
    with zipfile.ZipFile(package, "w") as archive:
        archive.writestr("a.txt", payload)
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps({"files": [{"path": "a.txt", "size": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}]}), encoding="utf-8")
    assert verify_release._verify_package_manifest(package, manifest) is None
    manifest.write_text(json.dumps({"files": [{"path": "missing.txt", "size": 1, "sha256": "0" * 64}]}), encoding="utf-8")
    assert "missing manifest" in (verify_release._verify_package_manifest(package, manifest) or "")


def test_proof_and_revocation_helpers(tmp_path: Path) -> None:
    proof = tmp_path / "proof.md"
    proof.write_text("- Installer SHA256: " + "A" * 64 + "\n", encoding="utf-8")
    assert verify_release._proof_installer_sha256(proof) == "A" * 64
    manifest = tmp_path / "m.json"
    manifest.write_text("{}", encoding="utf-8")
    digest = hashlib.sha256(manifest.read_bytes()).hexdigest().upper()
    revoked = tmp_path / "revoked.txt"
    revoked.write_text(digest + " | test reason\n", encoding="utf-8")
    assert verify_release._revoked(manifest, str(revoked)) == "test reason"


def test_pinned_key_mismatch_rejected(tmp_path: Path) -> None:
    wrong = tmp_path / "wrong.pem"
    wrong.write_text("not the key", encoding="utf-8")
    with pytest.raises(ValueError):
        verify_release._load_pinned_public_key(str(wrong))


def test_sanitize_detects_secret_and_rewrites(tmp_path: Path, monkeypatch, capsys) -> None:
    target = tmp_path / "a.txt"
    target.write_text("token = 'abcdefghijklmnop'", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", ["sanitize", str(tmp_path), "--strict"])
    assert sanitize_for_release.main() == 1
    assert "secret-like findings" in capsys.readouterr().out
    monkeypatch.setattr(sys, "argv", ["sanitize", str(tmp_path), "--qq", "12345", "--apply"])
    target.write_text("qq=12345", encoding="utf-8")
    assert sanitize_for_release.main() == 0
    assert "YOUR_QQ_ID" in target.read_text(encoding="utf-8")


def test_totp_recovery_code_and_enrollment(tmp_path: Path, monkeypatch) -> None:
    assert len(totp_material.recovery_code()) == 8
    fake_win32 = types.SimpleNamespace(
        CryptProtectData=lambda *args, **kwargs: b"encrypted",
        CryptUnprotectData=lambda *args, **kwargs: ("", b"SECRET"),
    )
    monkeypatch.setitem(sys.modules, "win32crypt", fake_win32)
    monkeypatch.setattr(totp_material.pyotp, "random_base32", lambda: "JBSWY3DPEHPK3PXP")
    vault = tmp_path / "vault"
    secret = vault / "secret.bin"
    recovery = vault / "recovery.txt"
    qr = vault / "qr.png"
    monkeypatch.setattr(totp_material, "write_qr", lambda *args: qr.write_bytes(b"png"))
    args = ["totp", "--vault", str(vault), "--secret", str(secret), "--recovery", str(recovery), "--qr", str(qr)]
    monkeypatch.setattr(sys, "argv", args)
    assert totp_material.main() == 0
    assert secret.read_bytes() == b"encrypted"
    assert recovery.is_file()
    assert (vault / "recovery_hashes.json").is_file()


def test_verify_release_error_paths(tmp_path: Path) -> None:
    bad = tmp_path / "bad.zip"
    bad.write_bytes(b"not a zip")
    assert verify_release._zip_installer_sha256(bad) is None
    assert verify_release._verify_package_manifest(bad, bad) is not None
    proof = tmp_path / "missing-proof.md"
    proof.write_text("no hash here", encoding="utf-8")
    assert verify_release._proof_installer_sha256(proof) is None
    manifest = tmp_path / "m.json"
    manifest.write_text("{}", encoding="utf-8")
    assert verify_release._revoked(manifest, "") is None
    assert verify_release._legacy_pinned(manifest, proof) is False


def test_totp_write_qr_real(tmp_path: Path) -> None:
    target = tmp_path / "qr.png"
    totp_material.write_qr("JBSWY3DPEHPK3PXP", target, "CBS", "owner")
    assert target.is_file() and target.stat().st_size > 0


def test_sanitize_skips_ignored_directory(tmp_path: Path) -> None:
    ignored = tmp_path / ".git"
    ignored.mkdir()
    (ignored / "x.txt").write_text("token = 'abcdefghijklmnop'", encoding="utf-8")
    assert list(sanitize_for_release.iter_text_files(tmp_path)) == []
