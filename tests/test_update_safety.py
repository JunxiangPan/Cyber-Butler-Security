"""Safety tests for the self-updater core.

These tests never download a real release and never restart services. They
verify that update paths are allow-listed, archives cannot escape staging, and
user data cannot be overwritten.
"""

from __future__ import annotations

import hashlib
import json
import zipfile
from pathlib import Path

import pytest

import update_core


def _zip(path: Path, files: dict[str, bytes], manifest: dict | None = None) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)
        if manifest is not None:
            archive.writestr(
                "update-manifest.json",
                json.dumps(manifest, ensure_ascii=False),
            )


def _manifest(entries: list[tuple[str, bytes]]) -> dict:
    files = [
        {
            "path": name,
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
        for name, data in entries
    ]
    return {"schema": 1, "version": "1.0.7", "files": files}


def test_manifest_rejects_data_and_config_paths() -> None:
    for path in ("AstrBot/data/chat.db", "AstrBot/data/cmd_config.json", "tools/broker_token.txt"):
        with pytest.raises(update_core.UpdateSafetyError):
            update_core.validate_manifest(
                {"schema": 1, "version": "1.0.7", "files": [{"path": path, "size": 0, "sha256": "0" * 64}]}
            )


def test_manifest_rejects_traversal() -> None:
    with pytest.raises(update_core.UpdateSafetyError):
        update_core.validate_manifest(
            {"schema": 1, "version": "1.0.7", "files": [{"path": "tools/../data/x.py", "size": 0, "sha256": "0" * 64}]}
        )


def test_archive_rejects_a_data_member_before_writing(tmp_path: Path) -> None:
    archive = tmp_path / "bad.zip"
    _zip(
        archive,
        {
            "tools/ok.py": b"ok",
            "AstrBot/data/chat.db": b"do not touch",
        },
    )
    staging = tmp_path / "staging"
    with pytest.raises(update_core.UpdateSafetyError):
        update_core.extract_zip(archive, staging)
    assert not (staging / "tools" / "ok.py").exists()
    assert not (staging / "AstrBot" / "data" / "chat.db").exists()


def test_archive_rejects_zip_slip(tmp_path: Path) -> None:
    archive = tmp_path / "slip.zip"
    _zip(archive, {"../escape.py": b"bad"})
    with pytest.raises(update_core.UpdateSafetyError):
        update_core.extract_zip(archive, tmp_path / "staging")


def test_hash_mismatch_does_not_replace_target(tmp_path: Path) -> None:
    source = tmp_path / "staging" / "tools" / "new.py"
    source.parent.mkdir(parents=True)
    source.write_bytes(b"new content")
    target = tmp_path / "target" / "tools" / "new.py"
    target.parent.mkdir(parents=True)
    target.write_bytes(b"old content")
    manifest = {
        "schema": 1,
        "version": "1.0.7",
        "files": [{"path": "tools/new.py", "size": len(b"new content"), "sha256": "0" * 64}],
    }
    with pytest.raises(update_core.UpdateSafetyError):
        update_core.apply_update(tmp_path / "staging", tmp_path / "target", update_core.validate_manifest(manifest))
    assert target.read_bytes() == b"old content"


def test_apply_preserves_user_data_and_installs_code(tmp_path: Path) -> None:
    data_dir = tmp_path / "target" / "AstrBot" / "data"
    data_dir.mkdir(parents=True)
    (data_dir / "chat.db").write_bytes(b"user data")
    (data_dir / "cmd_config.json").write_text('{"private": true}', encoding="utf-8")

    content = b"print('new code')\n"
    manifest = _manifest([("tools/new.py", content)])
    staging = tmp_path / "staging"
    staging.mkdir()
    _zip(staging / "release.zip", {"tools/new.py": content}, manifest)
    parsed = update_core.extract_zip(staging / "release.zip", staging / "extracted")
    applied = update_core.apply_update(staging / "extracted", tmp_path / "target", parsed)

    assert applied == ["tools/new.py"]
    assert (tmp_path / "target" / "tools" / "new.py").read_bytes() == content
    assert (data_dir / "chat.db").read_bytes() == b"user data"
    assert (data_dir / "cmd_config.json").read_text(encoding="utf-8") == '{"private": true}'
