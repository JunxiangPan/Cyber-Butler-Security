"""Security scanner and version compatibility tests.

The scanner is a PowerShell script; these tests only run on Windows and invoke
it as a black box, which also proves the packaged entry point works.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCANNER = ROOT / "tools" / "plugin_security_scanner.ps1"
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "plugins"

pytestmark = pytest.mark.skipif(sys.platform != "win32", reason="PowerShell scanner")


def run_scanner(path: Path) -> dict:
    completed = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(SCANNER),
            "-Path",
            str(path),
            "-Json",
        ],
        capture_output=True,
        text=True,
        timeout=90,
    )
    text = completed.stdout
    return json.loads(text[text.find("{") :])


def test_high_risk_plugin_is_unsafe() -> None:
    report = run_scanner(FIXTURES / "high_risk")
    assert report["Verdict"] == "unsafe"
    assert report["High"] >= 4
    rules = {finding["RuleId"] for finding in report["Findings"]}
    assert {"PY001", "PY002", "PY003", "PY005"} <= rules
    assert any(finding["File"] == "main.py" for finding in report["Findings"])


def test_clean_plugin_is_safe() -> None:
    report = run_scanner(FIXTURES / "clean")
    assert report["Verdict"] == "safe"
    assert report["High"] == 0
    assert report["Findings"] == []


def test_missing_directory_reports_error(tmp_path: Path) -> None:
    report = run_scanner(tmp_path / "does-not-exist")
    assert report["Verdict"] == "error"
    assert report["Error"]


@pytest.mark.parametrize(
    ("spec", "expected"),
    [
        (">=4.24,<5", True),
        (">=4.17.0", True),
        ("*", True),
        ("4.29.3", True),
        (">=5.0", False),
        ("<4.0", False),
    ],
)
def test_version_specs(spec: str, expected: bool) -> None:
    script = (
        "& {{ . '{scanner}'; "
        "(Test-AstrBotVersionSpec -Spec '{spec}' -Version '4.29.3') | "
        "ConvertTo-Json -Compress }}"
    ).format(scanner=SCANNER, spec=spec)
    output = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
        capture_output=True,
        text=True,
        timeout=60,
    ).stdout
    result = json.loads(output[output.find("{") :])
    assert result["Ok"] is expected
