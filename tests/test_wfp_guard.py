from __future__ import annotations

import ipaddress

import wfp_guard


def _policy():
    return {
        "schema": 1,
        "mode": "enforce",
        "service_account": "CyberButlerSvc",
        "allow": [{"kind": "loopback", "port": 18090}],
        "block_unknown": True,
    }


def test_block_plan_covers_all_ipv4_except_loopback():
    plan = wfp_guard.build_block_plan(_policy(), resolve=False)
    blocked = [ipaddress.ip_network(item) for item in plan.blocked]
    allowed = [ipaddress.ip_network(item) for item in plan.allowed]
    # No overlap between allowed and blocked.
    assert not any(net.subnet_of(permit) for net in blocked for permit in allowed)
    # Every address outside loopback is covered by a blocked network.
    for address in ("8.8.8.8", "192.0.2.1", "203.0.113.5"):
        ip = ipaddress.ip_address(address)
        assert any(ip in net for net in blocked)
    assert all(ipaddress.ip_address("127.0.0.1") in net for net in allowed)


def test_audit_mode_does_not_install_filters():
    policy = _policy()
    policy["mode"] = "audit"
    assert wfp_guard.build_apply_commands(policy, "S-1-5-18") == []


def test_apply_commands_are_sid_bound_and_blocking():
    commands = wfp_guard.build_apply_commands(_policy(), "S-1-5-18")
    assert commands
    assert all("-LocalUser 'S-1-5-18'" in item for item in commands)
    assert all("-Action Block" in item for item in commands)


def test_apply_policy_downgrades_enforce_without_opt_in(monkeypatch):
    monkeypatch.setattr(wfp_guard, "_sid", lambda account: "S-1-5-18")
    monkeypatch.setattr(wfp_guard, "remove_policy", lambda: None)
    monkeypatch.setattr(wfp_guard, "build_apply_commands", lambda *a, **k: [])
    policy = _policy()
    result = wfp_guard.apply_policy(policy)
    assert result["mode"] == "audit"
    assert result["applied"] == 0
