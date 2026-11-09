"""P2-05: weekly verify is executable, not a stub."""
from pathlib import Path

WORKFLOW = Path(".github/workflows/verify-release-weekly.yml")


def test_weekly_verify_calls_real_verifier() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "schedule:" in text
    assert "workflow_dispatch:" in text
    assert "gh release download" in text
    assert "--verify-release" in text
    assert "RELEASE_ASSETS.sha256" in text
