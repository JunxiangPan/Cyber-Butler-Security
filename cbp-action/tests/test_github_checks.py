"""GitHub Checks parser."""
from tools.github_checks import parse_gates


def test_parse_gate_statuses() -> None:
    text = "encoding: PASS\ncoverage: FAIL\ncustom: SKIPPED (not configured)\nCBP_RESULT=FAIL"
    assert parse_gates(text) == [("encoding", "PASS"), ("coverage", "FAIL"), ("custom", "SKIPPED")]
