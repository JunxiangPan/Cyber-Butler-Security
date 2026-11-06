"""Direct edge tests for the rule-source auditor."""
from __future__ import annotations

import json
from pathlib import Path

from tools import audit_rule_sources as audit_tool


def test_rule_id_and_node_validation() -> None:
    assert audit_tool._valid_rule_id("CBP-TST-001") is True
    assert audit_tool._valid_rule_id("TST-001") is False
    assert audit_tool._valid_node("tests/test.py::test_one") is True
    assert audit_tool._valid_node("tests\\test.py::test_one") is False
    assert audit_tool._valid_node("tests/test.py::") is False


def test_ast_module_scan_ignores_nested_and_rejects_bad_values(tmp_path) -> None:
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "good.py").write_text(
        'RULE_ID = "CBP-TST-001"\n'
        'def inner():\n'
        '    RULE_ID = "CBP-NESTED-001"\n'
        'OTHER = "RULE_ID = \\"CBP-COMMENT-001\\""\n',
        encoding="utf-8",
    )
    found, errors = audit_tool._module_rule_ids(tmp_path / "src")
    assert found == {"CBP-TST-001": str(tmp_path / "src" / "good.py")}
    assert errors == []


def test_ast_scan_reports_parse_and_non_string(tmp_path) -> None:
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "broken.py").write_text("def broken(:\n", encoding="utf-8")
    (tmp_path / "src" / "bad.py").write_text("RULE_ID = 123\n", encoding="utf-8")
    _found, errors = audit_tool._module_rule_ids(tmp_path / "src")
    assert any("ERROR parse" in item for item in errors)
    assert any("must be a string literal" in item for item in errors)


def test_registry_errors(tmp_path) -> None:
    path = tmp_path / "registry.json"
    path.write_text("{bad", encoding="utf-8")
    rules, errors = audit_tool._load_registry(path)
    assert rules == [] and errors
    path.write_text('{"rules": []}', encoding="utf-8")
    _rules, errors = audit_tool._load_registry(path)
    assert any("non-empty" in item for item in errors)
    path.write_text(json.dumps({"rules": [{"id": "bad"}]}), encoding="utf-8")
    _rules, errors = audit_tool._load_registry(path)
    assert any("invalid rule id" in item for item in errors)


def test_registry_rule_shape_errors(tmp_path) -> None:
    path = tmp_path / "registry.json"
    path.write_text(json.dumps({"rules": [{
        "id": "CBP-TST-001",
        "gate": "test",
        "source": {},
        "negative_test": "tests/test.py::n",
        "positive_test": "tests/test.py::p",
        "status": "paused",
    }]}), encoding="utf-8")
    _rules, errors = audit_tool._load_registry(path)
    assert any("source.project" in item for item in errors)
    assert any("status" in item for item in errors)


def test_changelog_errors(tmp_path) -> None:
    path = tmp_path / "changelog.md"
    path.write_text("no table\n", encoding="utf-8")
    rows, errors = audit_tool._load_changelog(path)
    assert rows == {} and any("missing Rule ID table" in item for item in errors)
    path.write_text(
        "| Rule ID | Component | Source PR | Source issue | Failure class | Negative test | Positive test | Status |\n"
        "|---|---|---|---|---|---|---|---|\n"
        "| CBP-TST-001 | CBP | p | i | f | a | b | active |\n"
        "| CBP-TST-001 | CBP | p | i | f | a | b | active |\n",
        encoding="utf-8",
    )
    _rows, errors = audit_tool._load_changelog(path)
    assert any("duplicate rule id" in item for item in errors)


def test_cli_success_and_failure(tmp_path, capsys) -> None:
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "rule.py").write_text('RULE_ID = "CBP-TST-001"\n', encoding="utf-8")
    (tmp_path / "tests").mkdir()
    (tmp_path / "tests" / "test_rule.py").write_text(
        "def test_negative():\n    assert True\n\ndef test_positive():\n    assert True\n",
        encoding="utf-8",
    )
    (tmp_path / "rules").mkdir()
    (tmp_path / "rules" / "registry.json").write_text(json.dumps({"rules": [{
        "id": "CBP-TST-001",
        "gate": "test",
        "description": "edge",
        "source": {"project": "CBP", "pr": "p", "issue": "i", "seed": True},
        "negative_test": "tests/test_rule.py::test_negative",
        "positive_test": "tests/test_rule.py::test_positive",
        "status": "active",
    }]}), encoding="utf-8")
    (tmp_path / "RULES-CHANGELOG.md").write_text(
        "| Rule ID | Component | Source PR | Source issue | Failure class | Negative test | Positive test | Status |\n"
        "|---|---|---|---|---|---|---|---|\n"
        "| CBP-TST-001 | CBP | p | i | f | tests/test_rule.py::test_negative | tests/test_rule.py::test_positive | active |\n",
        encoding="utf-8",
    )
    assert audit_tool.main(["--root", str(tmp_path)]) == 0
    assert "RULE_SOURCE_AUDIT_OK" in capsys.readouterr().out
    (tmp_path / "src" / "rule.py").write_text('RULE_ID = "CBP-TST-999"\n', encoding="utf-8")
    assert audit_tool.main(["--root", str(tmp_path)]) == 1
    assert "RULE_SOURCE_AUDIT_FAILED" in capsys.readouterr().out


def test_code_scan_invalid_duplicate_and_skip(tmp_path) -> None:
    (tmp_path / "src" / "nested").mkdir(parents=True)
    (tmp_path / "src" / "nested" / "skip.py").write_text('RULE_ID = "CBP-TST-001"\n', encoding="utf-8")
    (tmp_path / "src" / "bad.py").write_text(
        'RULE_ID = "bad"\n'
        'RULE_ID, OTHER = ("CBP-TST-002", 1)\n',
        encoding="utf-8",
    )
    (tmp_path / "src" / "dup.py").write_text('RULE_ID = "CBP-TST-001"\n', encoding="utf-8")
    found, errors = audit_tool._module_rule_ids(tmp_path / "src")
    assert "CBP-TST-001" in found
    assert any("invalid rule id" in item for item in errors)
    assert any("Duplicate rule id" in item for item in errors)
    _ = (tmp_path / "src" / "nested" / "skip.py").read_text(encoding="utf-8")


def test_registry_non_object_and_duplicate(tmp_path) -> None:
    path = tmp_path / "registry.json"
    path.write_text(json.dumps({"rules": ["not-an-object"]}), encoding="utf-8")
    _rules, errors = audit_tool._load_registry(path)
    assert any("rule must be an object" in item for item in errors)
    path.write_text(json.dumps({"rules": [
        {"id": "CBP-TST-001", "gate": "t", "source": {"project": "p", "pr": "p", "issue": "i"},
         "negative_test": "tests/a.py::n", "positive_test": "tests/a.py::p", "status": "active"},
        {"id": "CBP-TST-001", "gate": "t", "source": {"project": "p", "pr": "p", "issue": "i"},
         "negative_test": "tests/a.py::n", "positive_test": "tests/a.py::p", "status": "active"},
    ]}), encoding="utf-8")
    _rules, errors = audit_tool._load_registry(path)
    assert any("duplicate rule id" in item for item in errors)


def test_registry_invalid_test_node(tmp_path) -> None:
    path = tmp_path / "registry.json"
    path.write_text(json.dumps({"rules": [{
        "id": "CBP-TST-001", "gate": "t", "source": {"project": "p", "pr": "p", "issue": "i"},
        "negative_test": "tests/a.py::n", "positive_test": "bad-node", "status": "active",
    }]}), encoding="utf-8")
    _rules, errors = audit_tool._load_registry(path)
    assert any("positive_test" in item for item in errors)


def test_changelog_malformed_and_invalid(tmp_path) -> None:
    path = tmp_path / "changelog.md"
    path.write_text(
        "| Rule ID | Component | Source PR | Source issue | Failure class | Negative test | Positive test | Status |\n"
        "|---|---|---|---|---|---|---|---|\n"
        "| only | one |\n"
        "| bad-id | CBP | p | i | f | a | b | active |\n",
        encoding="utf-8",
    )
    _rows, errors = audit_tool._load_changelog(path)
    assert any("malformed row" in item for item in errors)
    assert any("invalid rule id" in item for item in errors)


def test_run_node_timeout_and_launch_error(monkeypatch, tmp_path) -> None:
    import subprocess
    from unittest import mock

    with mock.patch.object(audit_tool.subprocess, "run", side_effect=subprocess.TimeoutExpired("pytest", 1)):
        ok, reason, _code = audit_tool._run_node(tmp_path, "tests/a.py::n", False, "base")
        assert ok is False and reason == "timeout"
    with mock.patch.object(audit_tool.subprocess, "run", side_effect=OSError("cannot launch")):
        ok, reason, _code = audit_tool._run_node(tmp_path, "tests/a.py::n", False, "base")
        assert ok is False and "launch error" in reason


def test_main_with_explicit_paths(tmp_path, capsys) -> None:
    (tmp_path / "src").mkdir()
    (tmp_path / "tests").mkdir()
    (tmp_path / "rules").mkdir()
    (tmp_path / "src" / "r.py").write_text('RULE_ID = "CBP-TST-001"\n', encoding="utf-8")
    (tmp_path / "tests" / "test_r.py").write_text(
        "def test_n():\n    assert True\n\ndef test_p():\n    assert True\n", encoding="utf-8"
    )
    (tmp_path / "rules" / "registry.json").write_text(json.dumps({"rules": [{
        "id": "CBP-TST-001", "gate": "t", "source": {"project": "p", "pr": "p", "issue": "i"},
        "negative_test": "tests/test_r.py::test_n", "positive_test": "tests/test_r.py::test_p",
        "status": "active",
    }]}), encoding="utf-8")
    (tmp_path / "RULES-CHANGELOG.md").write_text(
        "| Rule ID | Component | Source PR | Source issue | Failure class | Negative test | Positive test | Status |\n"
        "|---|---|---|---|---|---|---|---|\n"
        "| CBP-TST-001 | CBP | p | i | f | tests/test_r.py::test_n | tests/test_r.py::test_p | active |\n",
        encoding="utf-8",
    )
    code = audit_tool.main([
        "--root", str(tmp_path),
        "--registry", str(tmp_path / "rules" / "registry.json"),
        "--changelog", str(tmp_path / "RULES-CHANGELOG.md"),
    ])
    assert code == 0
    assert "RULE_SOURCE_AUDIT_OK" in capsys.readouterr().out
