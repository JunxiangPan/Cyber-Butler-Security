from pathlib import Path
import json
import subprocess
import sys

TOOL = Path("tools/prebuild_freeze.py")
FILES = ("update-manifest.json", "BUILD_REPORT.md", "FINAL_QA_REPORT.md", "ACCEPTANCE_PROOF.md")


def test_freeze_create_and_tamper_fail(tmp_path: Path) -> None:
    for name in FILES:
        (tmp_path / name).write_text(name, encoding="utf-8")
    assert subprocess.run([sys.executable, str(TOOL), "--root", str(tmp_path), "--create"], check=False).returncode == 0
    assert subprocess.run([sys.executable, str(TOOL), "--root", str(tmp_path), "--verify"], check=False).returncode == 0
    (tmp_path / "BUILD_REPORT.md").write_text("changed", encoding="utf-8")
    assert subprocess.run([sys.executable, str(TOOL), "--root", str(tmp_path), "--verify"], check=False).returncode == 3


def test_freeze_missing_input_fails(tmp_path: Path) -> None:
    assert subprocess.run([sys.executable, str(TOOL), "--root", str(tmp_path), "--create"], check=False).returncode == 2


def test_freeze_extra_key_and_invalid_json_fail(tmp_path: Path) -> None:
    for name in FILES:
        (tmp_path / name).write_text(name, encoding="utf-8")
    subprocess.run([sys.executable, str(TOOL), "--root", str(tmp_path), "--create"], check=False)
    freeze = tmp_path / "pre-build-freeze.json"
    data = json.loads(freeze.read_text(encoding="utf-8")); data["extra"] = "x"
    freeze.write_text(json.dumps(data), encoding="utf-8")
    assert subprocess.run([sys.executable, str(TOOL), "--root", str(tmp_path), "--verify"], check=False).returncode == 3
    freeze.write_text("not json", encoding="utf-8")
    assert subprocess.run([sys.executable, str(TOOL), "--root", str(tmp_path), "--verify"], check=False).returncode == 2
