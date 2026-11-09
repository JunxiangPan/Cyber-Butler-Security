"""P0-07: mock reports exercise every publish-blocking branch."""
from tools.v17_orchestrator import decide


def gate(status="PASS", ratio=0.0, blocking=False):
    return {"gate_status": status, "skip_ratio": ratio, "blocking_skip": blocking}


def test_full_pass_allows_publish():
    assert decide("success", gate(), gate(), "a", "a").publish is True


def test_main_ci_red_blocks_with_precondition():
    d = decide("failure", gate(), gate(), "a", "a")
    assert d.exit_code == 2 and d.gate_status == "PRECONDITION_FAIL" and not d.publish


def test_cbe_fail_blocks():
    d = decide("success", gate("FAIL"), gate(), "a", "a")
    assert d.exit_code == 3 and not d.publish


def test_cbp_fail_blocks():
    d = decide("success", gate(), gate("FAIL"), "a", "a")
    assert d.exit_code == 3 and not d.publish


def test_skip_over_20_blocks_with_4():
    d = decide("success", gate(ratio=0.21), gate(), "a", "a")
    assert d.exit_code == 4 and not d.publish


def test_infra_is_explicit_and_blocks():
    d = decide("success", gate("SKIPPED_INFRA"), gate(), "a", "a")
    assert d.exit_code == 3 and d.gate_status == "SKIPPED_INFRA" and not d.publish


def test_tag_mismatch_blocks():
    d = decide("success", gate(), gate(), "a", "b")
    assert d.exit_code == 2 and not d.publish
