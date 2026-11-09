"""Static contract for Run-ReleasePipeline.ps1 -Unsigned (Windows execution later)."""
from pathlib import Path

SCRIPT = Path("tools/Run-ReleasePipeline.ps1")


def test_unsigned_mode_guard_and_skip_scope() -> None:
    text = SCRIPT.read_text(encoding="utf-8")
    assert "[switch]$Unsigned" in text
    assert "unsigned mode cannot have existing update-manifest.sig" in text
    assert "Build Mode: " in text
    assert "if (-not $Unsigned)" in text
    assert "verify RSA signature" in text
    assert "signature verification skipped by request" in text


def test_unsigned_does_not_skip_quality_gates() -> None:
    text = SCRIPT.read_text(encoding="utf-8")
    for gate in ("quality/preflight.py", "quality/run_quality_matrix.py",
                 "ACCEPTANCE_PROOF.md", "tools/package_release.py"):
        assert gate in text


def test_proof_source_and_freeze_order() -> None:
    text = SCRIPT.read_text(encoding="utf-8")
    assert "$ProofPath" in text and "$ProofSource" in text
    assert "proof_source" in text
    assert "unsigned build requires -ProofPath" in text
    report_pos = text.index("$reportHash = (Get-FileHash")
    freeze_pos = text.index("freeze unsigned artifact")
    sig_pos = text.index("if (-not $Unsigned)")
    assert report_pos < freeze_pos < sig_pos
