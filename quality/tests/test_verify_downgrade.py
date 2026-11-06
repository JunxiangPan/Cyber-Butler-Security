"""A forged old-version manifest must not pass verify_release."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_old_version_without_legacy_is_rejected(tmp_path: Path) -> None:
    manifest = tmp_path / "update-manifest.json"; signature = tmp_path / "update-manifest.sig"
    manifest.write_text('{"version":"1.6.3"}', encoding="utf-8")
    signature.write_text("AAAA", encoding="ascii")
    result = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "verify_release.py"), "--manifest", str(manifest), "--signature", str(signature)],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 1
    assert "DOWNGRADE_REJECTED" in result.stdout
