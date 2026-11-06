"""An empty gate set must never be reported as PASS."""
from __future__ import annotations

from pathlib import Path

from cbp import cli


def test_all_disabled_is_failure(tmp_path: Path, capsys) -> None:
    cfg = tmp_path / "cbp.json"
    cfg.write_text('{"schema_version":"0.1.3","enable_encoding":false,"enable_coverage":false,"enable_dependency":false,"enable_comments":false,"enable_docs":false,"enable_binary":false,"enable_claims":false,"enable_custom":false,"enable_upgrade":false}', encoding="utf-8")
    code = cli.main(["--root", str(tmp_path), "--config", str(cfg), "--mode", "enforce"])
    output = capsys.readouterr().out
    assert code == 1
    assert "CBP_RESULT=FAIL gates_ran=0" in output
