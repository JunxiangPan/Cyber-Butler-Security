"""Snapshot semantics: baseline restore, mutual exclusion."""
from pathlib import Path
import subprocess

SCRIPT = Path("tools/vm-snapshot-rollback.ps1")


def test_snapshot_script_contract() -> None:
    text = SCRIPT.read_text(encoding="utf-8")
    assert "cbs-acceptance-baseline" in text
    assert "cannot specify both -Restore and -Rollback" in text
    assert "exit 2" in text


def test_restore_and_rollback_together_exit_2() -> None:
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-File", str(SCRIPT), "-VMName", "x", "-Restore", "-Rollback"],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 2
