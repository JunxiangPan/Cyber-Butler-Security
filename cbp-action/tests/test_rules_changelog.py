"""Rules changelog hash is enforced."""
import hashlib
from pathlib import Path
from cbp import custom_rules
from cbp.config import GateConfig


def test_changed_changelog_without_hash_update_fails(tmp_path: Path) -> None:
    (tmp_path / "docs").mkdir()
    changelog = tmp_path / "docs" / "RULES-CHANGELOG.md"
    changelog.write_text("initial\n", encoding="utf-8")
    lock = tmp_path / "rules" / "changelog.sha256"
    lock.parent.mkdir()
    lock.write_text(hashlib.sha256(changelog.read_bytes()).hexdigest() + "\n", encoding="utf-8")
    cfg = GateConfig(root=tmp_path, rules_changelog_manifest=lock)
    assert custom_rules.run(cfg)[0] is True
    changelog.write_text("changed without lock\n", encoding="utf-8")
    passed, detail = custom_rules.run(cfg)
    assert passed is False and "changelog changed" in detail
