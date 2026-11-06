"""Meta tests: the rule-source auditor must really detect bad fixtures."""
from __future__ import annotations

import json
from pathlib import Path

from tools.audit_rule_sources import audit

RULE_ID = "CBP-TST-001"
NEGATIVE = "tests/test_rule.py::test_negative"
POSITIVE = "tests/test_rule.py::test_positive"


def _write_fixture(
    root: Path,
    *,
    code_ids: tuple[str, ...] = (RULE_ID,),
    registry_ids: tuple[str, ...] = (RULE_ID,),
    negative_node: str = NEGATIVE,
    positive_node: str = POSITIVE,
    fail_negative: bool = False,
    fail_positive: bool = False,
    changelog: bool = True,
) -> None:
    source = root / "src"
    tests = root / "tests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    source.joinpath("rule.py").write_text(
        "\n".join(f'RULE_ID = "{rule_id}"' for rule_id in code_ids) + "\n",
        encoding="utf-8",
    )
    tests.joinpath("test_rule.py").write_text(
        "def test_negative():\n"
        f"    assert {not fail_negative}\n\n"
        "def test_positive():\n"
        f"    assert {not fail_positive}\n",
        encoding="utf-8",
    )
    rules = []
    for rule_id in registry_ids:
        rules.append({
            "id": rule_id,
            "gate": "test",
            "description": "meta fixture",
            "source": {"project": "CBP", "pr": "meta", "issue": "meta", "seed": True},
            "negative_test": negative_node,
            "positive_test": positive_node,
            "status": "active",
        })
    (root / "rules").mkdir()
    (root / "rules" / "registry.json").write_text(
        json.dumps({"version": 1, "rules": rules}), encoding="utf-8"
    )
    if changelog:
        lines = [
            "| Rule ID | Component | Source PR | Source issue | Failure class | Negative test | Positive test | Status |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for rule_id in registry_ids:
            lines.append(
                f"| {rule_id} | CBP | meta | meta | fixture | {negative_node} | {positive_node} | active |"
            )
        (root / "RULES-CHANGELOG.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def test_unregistered_rule_is_reported(tmp_path) -> None:
    _write_fixture(tmp_path, registry_ids=(), changelog=False)
    issues = audit(tmp_path)
    assert any("Unregistered rule: CBP-TST-001" in item for item in issues)


def test_unregistered_rule_clean_fixture_passes(tmp_path) -> None:
    _write_fixture(tmp_path)
    assert audit(tmp_path) == []


def test_orphaned_registry_entry_is_reported(tmp_path) -> None:
    _write_fixture(tmp_path, code_ids=())
    issues = audit(tmp_path)
    assert any("Orphaned registry entry: CBP-TST-001" in item for item in issues)


def test_orphaned_registry_clean_fixture_passes(tmp_path) -> None:
    _write_fixture(tmp_path)
    assert audit(tmp_path) == []


def test_missing_test_node_is_reported(tmp_path) -> None:
    _write_fixture(tmp_path, negative_node="tests/test_rule.py::test_missing")
    issues = audit(tmp_path)
    assert any("negative test not collected" in item for item in issues)


def test_missing_test_node_clean_fixture_passes(tmp_path) -> None:
    _write_fixture(tmp_path)
    assert audit(tmp_path) == []


def test_failing_negative_test_is_reported(tmp_path) -> None:
    _write_fixture(tmp_path, fail_negative=True)
    issues = audit(tmp_path)
    assert any("negative test assertion failed" in item for item in issues)


def test_failing_negative_test_clean_fixture_passes(tmp_path) -> None:
    _write_fixture(tmp_path)
    assert audit(tmp_path) == []


def test_missing_changelog_is_reported(tmp_path) -> None:
    _write_fixture(tmp_path, changelog=False)
    issues = audit(tmp_path)
    assert any("missing changelog entry" in item for item in issues)


def test_missing_changelog_clean_fixture_passes(tmp_path) -> None:
    _write_fixture(tmp_path)
    assert audit(tmp_path) == []
