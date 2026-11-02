from __future__ import annotations

import pytest

import wfp_policy


def test_policy_validation_defaults_and_loopback():
    policy = wfp_policy.validate({
        "schema": 1,
        "mode": "AUDIT",
        "service_account": "CyberButlerSvc",
        "allow": [{"kind": "loopback", "port": 18090}],
    })
    assert policy["mode"] == "audit"
    assert policy["block_unknown"] is True
    assert policy["allow"][0]["port"] == 18090


def test_policy_rejects_unknown_mode_and_bad_domain():
    with pytest.raises(wfp_policy.PolicyError):
        wfp_policy.validate({"schema": 1, "mode": "off", "service_account": "x"})
    with pytest.raises(wfp_policy.PolicyError):
        wfp_policy.validate({
            "schema": 1, "mode": "audit", "service_account": "x",
            "allow": [{"kind": "domain", "name": "https://bad", "port": 443}],
        })
