"""P1-03/P1-06/P1-07: publish gate and infra failures."""
from __future__ import annotations

from tools.v17_publish_gate import evaluate


def _ok():
    return {
        "main_ci": "success", "precondition_status": "PASS",
        "cbe_gate_status": "PASS", "cbp_gate_status": "PASS",
        "skip_ok": True, "tag_commit": "a", "ci_commit": "a", "rebuilt": False,
    }


def test_publish_allowed() -> None:
    assert evaluate(_ok()) == (True, [])


def test_main_ci_red_blocks() -> None:
    value = _ok(); value["main_ci"] = "failure"
    assert evaluate(value)[0] is False


def test_cbe_fail_blocks() -> None:
    value = _ok(); value["cbe_gate_status"] = "FAIL"
    assert evaluate(value)[0] is False


def test_cbp_fail_blocks() -> None:
    value = _ok(); value["cbp_gate_status"] = "FAIL"
    assert evaluate(value)[0] is False


def test_skip_over_threshold_blocks() -> None:
    value = _ok(); value["skip_ok"] = False
    assert evaluate(value)[0] is False


def test_tag_commit_mismatch_blocks() -> None:
    value = _ok(); value["tag_commit"] = "b"
    assert evaluate(value)[0] is False


def test_rebuild_blocks() -> None:
    value = _ok(); value["rebuilt"] = True
    assert evaluate(value)[0] is False
