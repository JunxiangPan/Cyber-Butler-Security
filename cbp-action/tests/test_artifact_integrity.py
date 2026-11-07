from pathlib import Path
import zipfile

from cbp import artifact_integrity
from cbp.config import GateConfig


def test_missing_required_artifact_is_rejected(tmp_path: Path) -> None:
    archive = tmp_path / "release.zip"
    with zipfile.ZipFile(archive, "w") as handle:
        handle.writestr("tools/broker.py", b"print('ok')\n")
    cfg = GateConfig(root=tmp_path, package_zip=archive, required_artifacts=["tools/broker_service.py"])
    findings = artifact_integrity.check(cfg)
    assert any("required artifact missing" in item for item in findings)


def test_naked_netstat_is_rejected(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(artifact_integrity, "SKIP_PARTS", set())
    (tmp_path / "bad.py").write_text("import subprocess\nsubprocess.run(['netstat', '-ano'])\n", encoding="utf-8")
    cfg = GateConfig(root=tmp_path)
    findings = artifact_integrity.check(cfg)
    assert any("naked external command" in item for item in findings)


def test_pythonpath_must_include_tools(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(artifact_integrity, "SKIP_PARTS", set())
    (tmp_path / "start.bat").write_text('set "PYTHONPATH=C:\CyberButler"\n', encoding="utf-8")
    cfg = GateConfig(root=tmp_path)
    assert any("PYTHONPATH must include tools" in item for item in artifact_integrity.check(cfg))
