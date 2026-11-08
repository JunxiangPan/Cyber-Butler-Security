"""Local mock for build-unsigned artifact consumption (not Windows dynamic run)."""
from pathlib import Path
import json
import subprocess
import sys

FREEZE = Path("tools/prebuild_freeze.py")


def test_unsigned_artifact_has_proof_freeze_and_no_sig(tmp_path: Path) -> None:
    (tmp_path / "update-manifest.json").write_text('{"version":"1.7.0"}', encoding="utf-8")
    (tmp_path / "BUILD_REPORT.md").write_text(
        "# BUILD_REPORT\n- Build Mode: unsigned\n- proof_source: vm-proof-job/1\n",
        encoding="utf-8",
    )
    (tmp_path / "FINAL_QA_REPORT.md").write_text("Overall: PASS", encoding="utf-8")
    (tmp_path / "ACCEPTANCE_PROOF.md").write_text(
        "# ACCEPTANCE_PROOF\n- Commit SHA: " + "a" * 40 + "\n- Overall: PASS\n",
        encoding="utf-8",
    )
    assert subprocess.run([sys.executable, str(FREEZE), "--root", str(tmp_path), "--create"], check=False).returncode == 0
    assert not (tmp_path / "update-manifest.sig").exists()
    assert json.loads((tmp_path / "pre-build-freeze.json").read_text(encoding="utf-8"))
    assert subprocess.run([sys.executable, str(FREEZE), "--root", str(tmp_path), "--verify"], check=False).returncode == 0
