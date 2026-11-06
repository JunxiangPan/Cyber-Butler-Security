"""CBP release-discipline gates must exist in the only supported pipeline."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_pipeline_rejects_dirty_or_unpushed_tree() -> None:
    text = (ROOT / "tools" / "Run-ReleasePipeline.ps1").read_text(encoding="utf-8-sig")
    assert "status --porcelain" in text
    assert "$releaseBranch = 'release/v' + $Version" in text
    assert "manifestVersion" in text
    assert "working tree is dirty" in text


def test_release_discipline_document_exists() -> None:
    text = (ROOT / "docs" / "RELEASE_DISCIPLINE.md").read_text(encoding="utf-8")
    assert "pushed" in text
    assert "failing-before/passing-after" in text


def test_security_contact_and_sla_exist() -> None:
    text = (ROOT / "SECURITY.md").read_text(encoding="utf-8")
    assert "security/advisories/new" in text
    assert "Disclosure SLA" in text
    assert "Disclaimer" in text
