"""v1.6.3 package boundary: CBS must not ship AstrBot or SnowLuma runtimes."""

from __future__ import annotations

from package_release import is_forbidden_payload


def test_external_runtime_payloads_are_forbidden():
    assert is_forbidden_payload("AstrBot/main.py")
    assert is_forbidden_payload("SnowLuma/index.mjs")
    assert is_forbidden_payload("astrbot/.venv/Scripts/python.exe")
    assert is_forbidden_payload("snowluma/config/webui.json")


def test_cbs_files_remain_allowed():
    assert not is_forbidden_payload("tools/broker.py")
    assert not is_forbidden_payload("installer/core-sources.json")
    assert not is_forbidden_payload("docs/README.md")
