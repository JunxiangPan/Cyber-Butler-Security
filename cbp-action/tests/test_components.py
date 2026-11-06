"""Self-audit tests for CBP's own gates."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
from cbp import binary_gate, claims_gate, comment_gate, config, coverage_gate, dependency_gate, docs_gate  # noqa: E402


def _cfg(tmp_path: Path, **kw):
    base = dict(root=tmp_path, coverage_json=tmp_path / "coverage.json", coverage_allowlist=tmp_path / "allow.json", policy_file="tools/broker_policy.py", target_files=("tools/broker.py",))
    base.update(kw)
    return config.GateConfig(**base)


def test_config_json_and_paths(tmp_path: Path) -> None:
    p = tmp_path / "cbp.json"
    p.write_text(json.dumps({"coverage_threshold": 81, "enable_binary": False, "coverage_json": "cov.json"}), encoding="utf-8")
    cfg = config.load_config(tmp_path, p)
    assert cfg.coverage_threshold == 81 and cfg.enable_binary is False
    assert cfg.path("x") == tmp_path / "x"


def test_coverage_success_and_failure(tmp_path: Path) -> None:
    allow = tmp_path / "allow.json"; allow.write_text('{"files":{}}', encoding="utf-8")
    data = {"files": {"tools/broker.py": {"summary": {"num_statements": 10}, "missing_lines": []}, "tools/broker_policy.py": {"summary": {"percent_covered": 90}}}}
    (tmp_path / "coverage.json").write_text(json.dumps(data), encoding="utf-8")
    cfg = _cfg(tmp_path)
    assert coverage_gate.run(cfg)[0] is True
    data["files"]["tools/broker.py"]["missing_lines"] = list(range(1, 10))
    (tmp_path / "coverage.json").write_text(json.dumps(data), encoding="utf-8")
    assert coverage_gate.run(cfg)[0] is False


def test_dependency_success_and_failure(tmp_path: Path) -> None:
    lock = tmp_path / "lock"; installer = tmp_path / "installer"
    cfg = _cfg(tmp_path, dependency_lock=lock, install_command=installer)
    assert dependency_gate.run(cfg)[0] is False
    installer.write_text("pip install --require-hashes -r requirements.lock\n", encoding="utf-8")
    lock.write_text("requests==2.0 \\\n    --hash=sha256:" + "a" * 64 + "\n", encoding="utf-8")
    assert dependency_gate.run(cfg)[0] is True


def test_comment_gate_rejects_slop_and_missing_doc(tmp_path: Path) -> None:
    src = tmp_path / "x.py"; cfg = _cfg(tmp_path, comment_files=("x.py",))
    src.write_text('def Public(value):\n    """Return value to the caller safely."""\n    return value  # Send email\n', encoding="utf-8")
    assert comment_gate.run(cfg)[0] is False
    src.write_text('def Public(value):\n    """Return value to the caller safely."""\n    return value\n', encoding="utf-8")
    assert comment_gate.run(cfg)[0] is True


def test_docs_gate_success_and_missing(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.json"; cfg = _cfg(tmp_path, docs_manifest=manifest)
    assert docs_gate.run(cfg)[0] is False
    target = tmp_path / "incident.md"; target.write_text("incident", encoding="utf-8")
    digest = hashlib.sha256(b"incident").hexdigest().upper()
    manifest.write_text(json.dumps({"files": [{"path": "incident.md", "sha256": digest}]}), encoding="utf-8")
    assert docs_gate.run(cfg)[0] is True


def test_binary_gate_no_large_binaries(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path, package_zip=None, binary_artifacts=tmp_path / "artifacts")
    assert binary_gate.run(cfg)[0] is True


def test_claims_gate_mismatch(tmp_path: Path) -> None:
    manifest = tmp_path / "quality-manifest.json"; notes = tmp_path / "docs" / "releases" / "RELEASE_NOTES_v1.6.4.md"
    notes.parent.mkdir(parents=True); notes.write_text("QUALITY_COUNTS: 12/26\n", encoding="utf-8")
    manifest.write_text(json.dumps({"counts": {"passed": 13, "total": 26}, "profile": "ci"}), encoding="utf-8")
    cfg = _cfg(tmp_path, claims_manifest=manifest, claims_notes=notes)
    assert claims_gate.run(cfg)[0] is False


def test_binary_gate_with_provenance(tmp_path: Path) -> None:
    import zipfile
    package = tmp_path / "pkg.zip"; payload = b"x" * 6000
    with zipfile.ZipFile(package, "w", zipfile.ZIP_STORED) as archive:
        archive.writestr("big.exe", payload)
    artifacts = tmp_path / "artifacts"; artifacts.mkdir()
    digest = hashlib.sha256(payload).hexdigest().upper()
    (artifacts / "big.exe.build.json").write_text(json.dumps({"sha256": digest, "size_bytes": len(payload)}), encoding="utf-8")
    (artifacts / "big.exe.sbom.json").write_text(json.dumps({"components": [{"name": "x"}]}), encoding="utf-8")
    cfg = _cfg(tmp_path, package_zip=package, binary_artifacts=artifacts, binary_limit_mb=0.001)
    assert binary_gate.run(cfg)[0] is True
    (artifacts / "big.exe.sbom.json").unlink()
    assert binary_gate.run(cfg)[0] is False


def test_claims_gate_success(tmp_path: Path) -> None:
    manifest = tmp_path / "quality-manifest.json"; notes = tmp_path / "docs" / "releases" / "RELEASE_NOTES_v1.6.4.md"
    notes.parent.mkdir(parents=True); notes.write_text("QUALITY_COUNTS: 12/26\n", encoding="utf-8")
    manifest.write_text(json.dumps({"counts": {"passed": 12, "total": 26}, "profile": "ci"}), encoding="utf-8")
    assert claims_gate.run(_cfg(tmp_path, claims_manifest=manifest, claims_notes=notes))[0] is True


def test_comment_gate_missing_docstring(tmp_path: Path) -> None:
    source = tmp_path / "x.py"; source.write_text("def Public(value):\n    return value\n", encoding="utf-8")
    assert comment_gate.run(_cfg(tmp_path, comment_files=("x.py",)))[0] is False


def test_dependency_gate_missing_hash(tmp_path: Path) -> None:
    lock = tmp_path / "lock"; installer = tmp_path / "installer"
    lock.write_text("requests==2.0\n", encoding="utf-8")
    installer.write_text("pip install --require-hashes -r requirements.lock\n", encoding="utf-8")
    assert dependency_gate.run(_cfg(tmp_path, dependency_lock=lock, install_command=installer))[0] is False


def test_docs_gate_hash_mismatch(tmp_path: Path) -> None:
    target = tmp_path / "incident.md"; target.write_text("one", encoding="utf-8")
    manifest = tmp_path / "manifest.json"; manifest.write_text(json.dumps({"files": [{"path": "incident.md", "sha256": "A" * 64}]}), encoding="utf-8")
    assert docs_gate.run(_cfg(tmp_path, docs_manifest=manifest))[0] is False


def test_coverage_windows_key_allowlist_and_missing_policy(tmp_path: Path) -> None:
    allow = tmp_path / "allow.json"; allow.write_text(json.dumps({"files": {"tools/broker.py": [{"lines": [1, 9]}]}}), encoding="utf-8")
    data = {"files": {"tools/broker.py": {"summary": {"num_statements": 10}, "missing_lines": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]}, "tools/broker_policy.py": {"summary": {"percent_covered": 90}}}}
    (tmp_path / "coverage.json").write_text(json.dumps(data), encoding="utf-8")
    cfg = _cfg(tmp_path, coverage_threshold=95)
    assert coverage_gate.run(cfg)[0] is False
    data["files"]["tools/broker.py"]["missing_lines"] = []
    (tmp_path / "coverage.json").write_text(json.dumps(data), encoding="utf-8")
    assert coverage_gate.run(cfg)[0] is True
    del data["files"]["tools/broker_policy.py"]
    (tmp_path / "coverage.json").write_text(json.dumps(data), encoding="utf-8")
    assert coverage_gate.run(cfg)[0] is False


def test_binary_gate_accepts_self_contained_scope(tmp_path: Path) -> None:
    import zipfile
    package = tmp_path / "pkg.zip"; payload = b"x" * 6000
    with zipfile.ZipFile(package, "w", zipfile.ZIP_STORED) as archive:
        archive.writestr("big.exe", payload)
    artifacts = tmp_path / "artifacts"; artifacts.mkdir()
    digest = hashlib.sha256(payload).hexdigest().upper()
    (artifacts / "big.exe.build.json").write_text(json.dumps({"sha256": digest, "size_bytes": len(payload)}), encoding="utf-8")
    (artifacts / "big.exe.sbom.json").write_text(json.dumps({"scope": "self-contained-runtime", "components": []}), encoding="utf-8")
    cfg = _cfg(tmp_path, package_zip=package, binary_artifacts=artifacts, binary_limit_mb=0.001)
    assert binary_gate.run(cfg)[0] is True
    (artifacts / "big.exe.sbom.json").write_text(json.dumps({"scope": "unknown-scope"}), encoding="utf-8")
    assert binary_gate.run(cfg)[0] is False
