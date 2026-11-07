"""Rule pack hash and CEL integration tests."""
import hashlib
import json
from pathlib import Path

from cbp import custom_rules
from cbp.config import GateConfig
from cbp.packs import PackError, load_pack


def test_pack_hash_mismatch_is_rejected(tmp_path: Path) -> None:
    pack = tmp_path / "pack.json"
    pack.write_text(json.dumps({"name": "baseline", "version": "1.0.0", "rules": []}), encoding="utf-8")
    assert load_pack(pack)["name"] == "baseline"
    try:
        load_pack(pack, "0" * 64)
    except PackError as exc:
        assert "hash mismatch" in str(exc)
    else:
        raise AssertionError("bad pack hash was accepted")


def test_pack_rules_and_cel_rule_are_evaluated(tmp_path: Path) -> None:
    (tmp_path / "a.py").write_text("secret = 1\n", encoding="utf-8")
    pack = tmp_path / "pack.json"
    pack.write_text(json.dumps({
        "name": "baseline", "version": "1.0.0",
        "rules": [{"name": "cel-secret", "cel": 'files.exists(t, t.matches(".*secret.*"))',
                   "files": ["a.py"], "message": "secret found", "mode": "enforce"}],
    }), encoding="utf-8")
    digest = hashlib.sha256(pack.read_bytes()).hexdigest()
    cfg = GateConfig(root=tmp_path, packs=({"path": "pack.json", "sha256": digest},))
    passed, detail = custom_rules.run(cfg)
    assert passed is False and "secret found" in detail
