"""Comment gate must not punish ordinary verb-first comments."""
from __future__ import annotations

from pathlib import Path

from cbp import comment_gate
from cbp.config import GateConfig


def test_ordinary_verb_comments_pass(tmp_path: Path) -> None:
    source = tmp_path / "x.py"
    source.write_text(
        'def public(value):\n'
        '    """Return the configured value to the caller."""\n'
        '    # set the retry count\n'
        '    # get the user record\n'
        '    # run the migration\n'
        '    # call the upstream API\n'
        '    return value\n',
        encoding="utf-8",
    )
    cfg = GateConfig(root=tmp_path, comment_files=("x.py",))
    assert comment_gate.run(cfg)[0] is True


def test_inline_suppression_ignores_rule(tmp_path: Path) -> None:
    source = tmp_path / "x.py"
    source.write_text(
        'def public(value):\n'
        '    """Return the configured value to the caller."""  # cbp: ignore=CBP-CMT-001\n'
        '    return value  # This is a function  # cbp: ignore=CBP-CMT-001\n',
        encoding="utf-8",
    )
    cfg = GateConfig(root=tmp_path, comment_files=("x.py",))
    assert comment_gate.run(cfg)[0] is True
