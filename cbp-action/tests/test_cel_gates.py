"""CEL gate policies are behavior-equivalent to the legacy decisions."""
import pytest
from cbp import cel_gates


@pytest.mark.parametrize("gate,context,expected", [
    ("comments", {"findings": []}, True),
    ("comments", {"findings": ["bad"]}, False),
    ("claims", {"ok": True}, True),
    ("claims", {"ok": False}, False),
    ("dependency", {"ok": True}, True),
    ("docs", {"ok": False}, False),
    ("custom", {"findings": []}, True),
    ("custom", {"findings": ["bad"]}, False),
])
def test_policy_decision(gate, context, expected):
    assert cel_gates.decide(gate, context) is expected


def test_override_policy():
    assert cel_gates.decide("claims", {"ok": False}, {"claims": "ok == false"}) is True
