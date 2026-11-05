"""Real Windows ACL enforcement test (no simulated ACL model)."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest


@pytest.mark.skipif(os.name != "nt", reason="Windows ACL only")
def test_kernel_acl_denies_write(tmp_path: Path) -> None:
    target = tmp_path / "sensitive"
    target.mkdir()
    user = os.environ.get("USERNAME", "")
    assert user
    subprocess.run(
        ["icacls", str(target), "/deny", f"{user}:(W)"],
        check=True,
        capture_output=True,
        text=True,
    )
    try:
        with pytest.raises(PermissionError):
            (target / "blocked.txt").write_text("x", encoding="utf-8")
    finally:
        subprocess.run(
            ["icacls", str(target), "/remove:d", user],
            check=False,
            capture_output=True,
            text=True,
        )
