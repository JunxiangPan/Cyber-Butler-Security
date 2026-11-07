"""Custom gate cache hits and invalidates on content change."""
from pathlib import Path
from cbp import custom_rules
from cbp.config import GateConfig


def test_cache_hit_and_invalidation(tmp_path, monkeypatch):
    (tmp_path / "a.py").write_text("print(1)\n", encoding="utf-8")
    cfg = GateConfig(root=tmp_path, cache_file=".cache.json",
                     custom_rules=({"name": "x", "pattern": "print", "files": ["*.py"], "message": "hit", "mode": "warn", "max_matches": 1},))
    calls = {"n": 0}
    original = custom_rules._detect
    def counted(c):
        calls["n"] += 1
        return original(c)
    monkeypatch.setattr(custom_rules, "_detect", counted)
    custom_rules.run(cfg)
    custom_rules.run(cfg)
    assert calls["n"] == 1
    (tmp_path / "a.py").write_text("changed\n", encoding="utf-8")
    custom_rules.run(cfg)
    assert calls["n"] == 2
