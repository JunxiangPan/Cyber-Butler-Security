"""v1.6.3 package boundary: CBS must not ship AgentRuntime or AuxRuntime runtimes."""

from __future__ import annotations

from package_release import is_forbidden_payload


def test_external_runtime_payloads_are_forbidden():
    assert is_forbidden_payload("AgentRuntime/main.py")
    assert is_forbidden_payload("AuxRuntime/index.mjs")
    assert is_forbidden_payload("agentruntime/.venv/Scripts/python.exe")
    assert is_forbidden_payload("auxruntime/config/webui.json")


def test_cbs_files_remain_allowed():
    assert not is_forbidden_payload("tools/broker.py")
    assert not is_forbidden_payload("installer/core-sources.json")
    assert not is_forbidden_payload("docs/README.md")
