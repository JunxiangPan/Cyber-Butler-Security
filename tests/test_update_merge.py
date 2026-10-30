"""Tests for local-overlay rendering and production merge safety."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

import update_core
import update_merge_core


def _manifest(entries: list[tuple[str, bytes]]) -> dict:
    return update_core.validate_manifest(
        {
            "schema": 1,
            "version": "1.0.7",
            "files": [
                {
                    "path": name,
                    "size": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
                for name, data in entries
            ],
        }
    )


def test_protected_data_and_tokens_are_rejected() -> None:
    assert update_merge_core.is_protected("AstrBot/data/chat.db")
    assert update_merge_core.is_protected("tools/broker_token.txt")
    assert update_merge_core.is_protected("local-overlay.json")
    assert not update_merge_core.is_protected("tools/broker.py")
    with pytest.raises(update_merge_core.MergeError):
        update_merge_core.validate_manifest_protected(
            {"files": [{"path": "AstrBot/data/chat.db"}]}
        )


def test_render_runtime_but_not_docs(tmp_path: Path) -> None:
    staging = tmp_path / "staging"
    (staging / "tools").mkdir(parents=True)
    (staging / "docs").mkdir()
    runtime = b"ROOT = r'YOUR_PROJECT_PATH'\n"
    doc = b"# YOUR_PROJECT_PATH\n"
    (staging / "tools" / "broker.py").write_bytes(runtime)
    (staging / "docs" / "guide.md").write_bytes(doc)
    manifest = _manifest(
        [
            ("tools/broker.py", runtime),
            ("docs/guide.md", doc),
        ]
    )
    rendered = update_merge_core.render_staging(
        staging,
        manifest,
        {"values": {"YOUR_PROJECT_PATH": r"D:\deployment"}},
    )
    assert (staging / "tools" / "broker.py").read_bytes() == b"ROOT = r'D:\\deployment'\n"
    assert (staging / "docs" / "guide.md").read_bytes() == doc
    assert any(item["path"] == "tools/broker.py" for item in rendered["files"])


def test_unresolved_placeholder_is_rejected(tmp_path: Path) -> None:
    staging = tmp_path / "staging"
    (staging / "tools").mkdir(parents=True)
    data = b"ROOT = 'YOUR_PROJECT_PATH'\nQQ = 'YOUR_QQ_ID'\n"
    (staging / "tools" / "broker.py").write_bytes(data)
    manifest = _manifest([("tools/broker.py", data)])
    with pytest.raises(update_merge_core.MergeError):
        update_merge_core.render_staging(
            staging,
            manifest,
            {"values": {"YOUR_PROJECT_PATH": r"D:\deployment"}},
        )


def test_overlay_plugin_patch_is_allowlisted_but_runtime_data_is_not() -> None:
    assert update_core.is_allowed_path(
        "overlay/astrbot/data/plugins/p/x.py"
    )
    assert not update_core.is_allowed_path(
        "overlay/astrbot/data/plugins/p/x.json"
    )
    assert not update_core.is_allowed_path("AstrBot/data/plugins/p/x.py")


def test_overlay_target_mapping_is_fixed() -> None:
    assert (
        update_merge_core.map_overlay_target("overlay/astrbot/core/x.py")
        == "AstrBot/astrbot/core/x.py"
    )
    assert (
        update_merge_core.map_overlay_target("overlay/astrbot/dashboard/x.py")
        == "AstrBot/astrbot/dashboard/x.py"
    )
    assert (
        update_merge_core.map_overlay_target(
            "overlay/astrbot/data/plugins/p/x.py"
        )
        == "AstrBot/data/plugins/p/x.py"
    )
    with pytest.raises(update_merge_core.MergeError):
        update_merge_core.map_overlay_target("overlay/astrbot/other/x.py")


def test_apply_overlay_backs_up_hashes_and_restores(tmp_path: Path) -> None:
    target = tmp_path / "target"
    core = target / "AstrBot" / "astrbot" / "core"
    plugin = target / "AstrBot" / "data" / "plugins" / "p"
    core.mkdir(parents=True)
    plugin.mkdir(parents=True)
    old_core = b"old core\n"
    old_plugin = b"old plugin\n"
    (core / "x.py").write_bytes(old_core)
    (plugin / "y.py").write_bytes(old_plugin)
    old_core_hash = hashlib.sha256(old_core).hexdigest()
    old_plugin_hash = hashlib.sha256(old_plugin).hexdigest()

    staging = tmp_path / "staging"
    (staging / "overlay" / "astrbot" / "core").mkdir(parents=True)
    (staging / "overlay" / "astrbot" / "data" / "plugins" / "p").mkdir(
        parents=True
    )
    new_core = b"new core\n"
    new_plugin = b"new plugin\n"
    (staging / "overlay" / "astrbot" / "core" / "x.py").write_bytes(new_core)
    (staging / "overlay" / "astrbot" / "data" / "plugins" / "p" / "y.py").write_bytes(
        new_plugin
    )
    manifest = _manifest(
        [
            ("overlay/astrbot/core/x.py", new_core),
            ("overlay/astrbot/data/plugins/p/y.py", new_plugin),
        ]
    )
    backup = target / "backups" / "overlay-test"
    result = update_merge_core.apply_overlay(
        staging, target, manifest, backup
    )
    assert len(result["applied"]) == 2
    assert (core / "x.py").read_bytes() == new_core
    assert (plugin / "y.py").read_bytes() == new_plugin
    assert (backup / "overlay-manifest.json").is_file()
    assert (backup / "AstrBot/astrbot/core/x.py").read_bytes() == old_core
    assert (backup / "AstrBot/data/plugins/p/y.py").read_bytes() == old_plugin

    update_merge_core.restore_overlay(backup, target)
    assert hashlib.sha256((core / "x.py").read_bytes()).hexdigest() == old_core_hash
    assert hashlib.sha256((plugin / "y.py").read_bytes()).hexdigest() == old_plugin_hash


def test_apply_overlay_skips_missing_plugin_without_creating_dirs(
    tmp_path: Path, monkeypatch
) -> None:
    target = tmp_path / "target"
    (target / "AstrBot" / "data" / "plugins").mkdir(parents=True)
    staging = tmp_path / "staging"
    (staging / "overlay" / "astrbot" / "data" / "plugins" / "missing").mkdir(
        parents=True
    )
    data = b"patch\n"
    (staging / "overlay" / "astrbot" / "data" / "plugins" / "missing" / "x.py").write_bytes(
        data
    )
    manifest = _manifest(
        [("overlay/astrbot/data/plugins/missing/x.py", data)]
    )
    warnings = []
    monkeypatch.setattr(
        update_merge_core.logger,
        "warning",
        lambda message, *args: warnings.append(message % args),
    )
    result = update_merge_core.apply_overlay(
        staging, target, manifest, target / "backups" / "overlay-skip"
    )
    assert result["applied"] == []
    assert result["skipped"] == ["overlay/astrbot/data/plugins/missing/x.py"]
    assert not (target / "AstrBot/data/plugins/missing").exists()
    assert warnings and "plugin missing" in warnings[0]


def test_apply_overlay_skips_manifest_file_missing_from_staging(
    tmp_path: Path, monkeypatch
) -> None:
    target = tmp_path / "target"
    core = target / "AstrBot" / "astrbot" / "core"
    core.mkdir(parents=True)
    old = b"old\n"
    (core / "x.py").write_bytes(old)
    staging = tmp_path / "staging"
    staging.mkdir()
    missing = b"missing\n"
    manifest = _manifest([("overlay/astrbot/core/x.py", missing)])
    warnings = []
    monkeypatch.setattr(
        update_merge_core.logger,
        "warning",
        lambda message, *args: warnings.append(message % args),
    )
    result = update_merge_core.apply_overlay(
        staging, target, manifest, target / "backups" / "overlay-missing"
    )
    assert result["applied"] == []
    assert result["skipped"] == ["overlay/astrbot/core/x.py"]
    assert (core / "x.py").read_bytes() == old
    assert warnings and "source missing" in warnings[0]


def test_apply_overlay_rolls_back_and_restores_original_hashes(
    tmp_path: Path, monkeypatch
) -> None:
    target = tmp_path / "target"
    core = target / "AstrBot" / "astrbot" / "core"
    core.mkdir(parents=True)
    old_first = b"old first\n"
    old_second = b"old second\n"
    (core / "a.py").write_bytes(old_first)
    (core / "b.py").write_bytes(old_second)

    staging = tmp_path / "staging"
    (staging / "overlay" / "astrbot" / "core").mkdir(parents=True)
    new_first = b"new first\n"
    new_second = b"new second\n"
    (staging / "overlay" / "astrbot" / "core" / "a.py").write_bytes(new_first)
    (staging / "overlay" / "astrbot" / "core" / "b.py").write_bytes(new_second)
    manifest = _manifest(
        [
            ("overlay/astrbot/core/a.py", new_first),
            ("overlay/astrbot/core/b.py", new_second),
        ]
    )
    original_hash = update_merge_core._hash_file
    failed = {"value": False}

    def failing_hash(path):
        if (
            Path(path) == core / "b.py"
            and Path(path).read_bytes() == new_second
            and not failed["value"]
        ):
            failed["value"] = True
            raise OSError("simulated overlay failure")
        return original_hash(path)

    monkeypatch.setattr(update_merge_core, "_hash_file", failing_hash)
    with pytest.raises((update_merge_core.MergeError, OSError)):
        update_merge_core.apply_overlay(
            staging, target, manifest, target / "backups" / "overlay-failure"
        )

    assert (core / "a.py").read_bytes() == old_first
    assert (core / "b.py").read_bytes() == old_second


def test_baseline_detects_local_change(tmp_path: Path) -> None:
    target = tmp_path / "target"
    (target / "tools").mkdir(parents=True)
    path = target / "tools" / "broker.py"
    path.write_bytes(b"old")
    digest = hashlib.sha256(b"old").hexdigest()
    overlay = {"values": {"YOUR_QQ_ID": "1"}, "baseline": {"tools/broker.py": digest}}
    assert update_merge_core.baseline_changes(target, overlay) == []
    path.write_bytes(b"local change")
    assert update_merge_core.baseline_changes(target, overlay) == ["tools/broker.py"]
