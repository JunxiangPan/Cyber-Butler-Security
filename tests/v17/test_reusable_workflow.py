"""P0-07: real reusable workflow uses mock CLIs and hard publish conditions."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

WORKFLOW = Path(".github/workflows/reusable-v17-release.yml")
MOCK_CBE = Path("tests/v17/mock/cbe_cli.py")
MOCK_CBP = Path("tests/v17/mock/cbp_cli.py")
CHECKER = Path("tools/v17_gate_report.py")


def test_workflow_has_required_jobs_and_publish_if() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    for job in ("preflight:", "cbe-gate:", "build-once:", "cbp-gate:", "publish:"):
        assert job in text
    assert "needs: [preflight, cbe-gate, build-once, cbp-gate]" in text
    assert "needs.cbe-gate.outputs.gate_status == 'PASS'" in text
    assert "needs.cbp-gate.outputs.gate_status == 'PASS'" in text
    assert "needs.cbp-gate.outputs.skip_ok == 'true'" in text
    assert "vars.CBE_CLI" in text and "vars.CBP_CLI" in text


def _run(mock: Path, checker_kind: str, mode: str) -> int:
    with tempfile.TemporaryDirectory() as temp:
        env = dict(os.environ, MOCK_MODE=mode, CBE_REPORT=f"{temp}/cbe.json", CBP_REPORT=f"{temp}/cbp.json")
        subprocess.run([sys.executable, str(mock)], env=env, check=False)
        report = f"{temp}/cbe.json" if checker_kind == "cbe" else f"{temp}/cbp.json"
        return subprocess.run([sys.executable, str(CHECKER), "--kind", checker_kind, "--report", report], check=False).returncode


def test_mock_gate_exit_codes() -> None:
    assert _run(MOCK_CBE, "cbe", "pass") == 0
    assert _run(MOCK_CBE, "cbe", "cbe-fail") == 3
    assert _run(MOCK_CBE, "cbe", "infra") == 3
    assert _run(MOCK_CBP, "cbp", "pass") == 0
    assert _run(MOCK_CBP, "cbp", "cbp-fail") == 3
    assert _run(MOCK_CBP, "cbp", "infra") == 3
    assert _run(MOCK_CBP, "cbp", "skip-over") == 4
