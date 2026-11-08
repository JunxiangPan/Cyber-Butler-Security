from pathlib import Path
import json
import subprocess
import sys

TOOL = Path("tools/signing_report.py")


def test_signing_report_roundtrip_and_tamper(tmp_path: Path) -> None:
    freeze = tmp_path / "pre-build-freeze.json"
    report = tmp_path / "signing-report.json"
    freeze.write_text(json.dumps({"update-manifest.json": "a", "BUILD_REPORT.md": "b", "FINAL_QA_REPORT.md": "c", "ACCEPTANCE_PROOF.md": "d"}), encoding="utf-8")
    assert subprocess.run([sys.executable, str(TOOL), "--freeze", str(freeze), "--report", str(report), "--create"], check=False).returncode == 0
    assert subprocess.run([sys.executable, str(TOOL), "--freeze", str(freeze), "--report", str(report), "--verify"], check=False).returncode == 0
    data = json.loads(report.read_text(encoding="utf-8")); data["payload_sha256"] = "0" * 64
    report.write_text(json.dumps(data), encoding="utf-8")
    assert subprocess.run([sys.executable, str(TOOL), "--freeze", str(freeze), "--report", str(report), "--verify"], check=False).returncode == 3


def test_signing_report_missing_freeze_fails(tmp_path: Path) -> None:
    assert subprocess.run([sys.executable, str(TOOL), "--freeze", str(tmp_path / "missing"), "--create"], check=False).returncode == 2


def test_signing_payload_uses_shared_jcs(tmp_path: Path) -> None:
    from tools.jcs import payload_sha256
    freeze = tmp_path / "pre-build-freeze.json"
    report = tmp_path / "signing-report.json"
    data = {"update-manifest.json": "a", "BUILD_REPORT.md": "b", "FINAL_QA_REPORT.md": "c", "ACCEPTANCE_PROOF.md": "d"}
    freeze.write_text(json.dumps(data), encoding="utf-8")
    subprocess.run([sys.executable, str(TOOL), "--freeze", str(freeze), "--report", str(report), "--create"], check=True)
    assert json.loads(report.read_text(encoding="utf-8"))["payload_sha256"] == payload_sha256(data)
