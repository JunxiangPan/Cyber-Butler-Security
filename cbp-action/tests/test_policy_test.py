"""Policy fixture runner tests."""
import json
from pathlib import Path
from cbp.policy_test import run_fixture


def test_policy_fixture_passes(tmp_path: Path) -> None:
    path = tmp_path / "fixtures.json"
    path.write_text(json.dumps({"cases": [
        {"name": "secret", "cel": 'files.exists(t, t.matches(".*secret.*"))', "files": {"a": "secret"}, "expect": True},
        {"name": "clean", "cel": 'files.exists(t, t.matches(".*secret.*"))', "files": {"a": "clean"}, "expect": False},
    ]}), encoding="utf-8")
    passed, failures = run_fixture(path)
    assert passed is True and failures == []
