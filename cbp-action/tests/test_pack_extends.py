"""Pack extends are recursive and hash-checked."""
import hashlib
import json
from pathlib import Path
from cbp.packs import load_pack


def test_pack_extends_and_hash(tmp_path: Path) -> None:
    base = tmp_path / "base.json"
    base.write_text(json.dumps({"name": "base", "version": "1.0.0", "rules": [{"name": "a"}]}), encoding="utf-8")
    child = tmp_path / "child.json"
    child.write_text(json.dumps({
        "name": "child", "version": "1.0.0",
        "extends": [{"path": "base.json", "sha256": hashlib.sha256(base.read_bytes()).hexdigest()}],
        "rules": [{"name": "b"}],
    }), encoding="utf-8")
    data = load_pack(child)
    assert [rule["name"] for rule in data["rules"]] == ["a", "b"]
