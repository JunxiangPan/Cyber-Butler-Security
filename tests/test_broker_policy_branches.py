"""Branch coverage for the isolated broker policy module."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import broker_policy as policy  # noqa: E402


def ctx(tmp_path: Path, config: Path | None = None) -> policy.PolicyContext:
    root = tmp_path / "root"; root.mkdir(exist_ok=True)
    shared = tmp_path / "shared"; shared.mkdir(exist_ok=True)
    return policy.PolicyContext(root=root, shared=shared, workspace_root=root / "workspace", default_workspace_root=tmp_path / "default-workspace", broker_config=config or (tmp_path / "missing.json"), tmp_roots=(tmp_path / "tmp",), memory_roots=(root / "memory",), totp_vault_root=root / "vault", critical_names=frozenset({"package.json", "conftest.py"}), protected_names=frozenset({"broker_config.json"}), log=lambda _message: None)


def test_config_roots_string_list_and_bad_json(tmp_path: Path) -> None:
    config = tmp_path / "broker.json"
    config.write_text(json.dumps({"workspace_root": "C:/one", "shared_roots": "C:/two"}), encoding="utf-8")
    assert any(str(root).endswith("one") for root in policy.workspace_roots(ctx(tmp_path, config)))
    config.write_text(json.dumps({"workspace_path": "C:/three", "shared_roots": ["C:/four"]}), encoding="utf-8")
    assert any(str(root).endswith("three") for root in policy.workspace_roots(ctx(tmp_path, config)))
    config.write_text("{bad", encoding="utf-8")
    assert policy.workspace_roots(ctx(tmp_path, config))


def test_config_log_failure_is_swallowed(tmp_path: Path) -> None:
    config = tmp_path / "bad.json"; config.write_text("{bad", encoding="utf-8")
    base = ctx(tmp_path, config)
    broken = policy.PolicyContext(**{**base.__dict__, "log": lambda _m: (_ for _ in ()).throw(RuntimeError("x"))})
    assert policy.workspace_roots(broken)


def test_resolve_failures_are_denied() -> None:
    with patch.object(Path, "resolve", side_effect=OSError("no")):
        assert policy.inside_any(Path("x"), (Path("y"),)) is False
        fake = policy.PolicyContext(Path("."), Path("."), Path("."), Path("."), Path("."), (), (), Path("."), frozenset(), frozenset(), lambda _m: None)
        assert policy.classify("delete", "x", fake) == "deny"


def test_workspace_text_and_inside_shared(tmp_path: Path) -> None:
    c = ctx(tmp_path)
    assert policy.workspace_text(str(c.workspace_root / "a"), c) is True
    assert policy.workspace_text(str(c.shared / "a"), c) is False
    assert policy.inside_shared(c.shared / "a", c) is True


def test_classify_actions_and_paths(tmp_path: Path) -> None:
    c = ctx(tmp_path)
    assert policy.classify("unknown", "x", c) == "deny"
    assert policy.classify("send", "http://example", c) == "totp"
    assert policy.classify("delete", str(c.totp_vault_root / "x"), c) == "deny"
    assert policy.classify("delete", str(c.tmp_roots[0] / "x"), c) == "allow"
    assert policy.classify("delete", str(c.workspace_root / "x"), c) == "totp"
    assert policy.classify("delete", str(c.memory_roots[0] / "x"), c) == "totp"
    assert policy.classify("write_file", str(c.shared / "new.txt"), c) == "allow"


def test_critical_and_rule_tampering(tmp_path: Path) -> None:
    c = ctx(tmp_path)
    assert policy.critical_integrity_hit(str(c.root / "package.json"), c) is True
    assert policy.critical_integrity_hit(str(c.root / ".claude" / "settings.json"), c) is True
    assert policy.critical_integrity_hit(str(c.root / ".github" / "workflows" / "x.yml"), c) is True
    assert policy.critical_integrity_hit(str(tmp_path / "outside.json"), c) is False
    assert policy.rule_tampering_hit(str(c.root / "tools" / "x"), c) is True
    assert policy.rule_tampering_hit(str(c.root / "x.chain.jsonl"), c) is True
    assert policy.rule_tampering_hit(str(c.root / "x" / "quarantine" / "y"), c) is True
    assert policy.rule_tampering_hit(str(tmp_path / "outside"), c) is False


def test_target_mode_and_bypass(tmp_path: Path) -> None:
    c = ctx(tmp_path)
    existing = c.shared / "x.txt"; existing.write_text("x", encoding="utf-8")
    assert policy.target_mode("write_file", str(existing)) == "replace"
    assert policy.target_mode("overwrite", str(existing)) == "replace"
    assert policy.target_mode("delete", str(existing)) == "delete"
    assert policy.bypass_scope("delete", str(existing)).startswith("delete:delete:")
    with patch.object(Path, "resolve", side_effect=OSError("no")):
        assert policy.target_mode("write_file", "x") == "replace"
