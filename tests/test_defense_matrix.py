"""Defense-matrix regression tests for the automated red-team suite.

The matrix reports PASS / FAIL / SKIP. WFP is intentionally SKIP while the
shipped guard remains audit-only; it must not be reported as a passing enforce
control.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import red_team_test as matrix  # noqa: E402


def _assert_not_failed(result: matrix.DefenseResult) -> None:
    print(f"[{result.status}] {result.name}: {result.detail}")
    assert result.status in {matrix.PASS, matrix.SKIP}, result.detail


def test_acl_restricted_read() -> None:
    _assert_not_failed(matrix.check_acl_file_read())


def test_broker_requires_totp() -> None:
    _assert_not_failed(matrix.check_broker_totp())


def test_toctou_tamper_is_blocked() -> None:
    _assert_not_failed(matrix.check_toctou())


def test_wfp_unknown_egress() -> None:
    _assert_not_failed(matrix.check_wfp_unknown_egress())


def test_defense_matrix_has_no_failures() -> None:
    results = matrix.run_all()
    print("\n=== Defense matrix ===")
    for result in results:
        print(f"[{result.status}] {result.name}: {result.detail}")
    assert not [r for r in results if r.status == matrix.FAIL]
