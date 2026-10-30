#!/usr/bin/env python3
"""Rehearse and backfill LivingMemory ``memory_sources`` safely.

This tool never writes the production DB during rehearsal. It copies the
source databases into a work directory, writes only the copied DB, verifies
the result, then restores the copy from a backup and runs integrity_check.

Modes:
    rehearse   backup -> dry-run -> apply -> verify -> rollback -> verify
    dry-run    report expected source windows, no write
    apply      write to WORKDIR/livingmemory.db only
    verify     validate source rows and integrity
    rollback   restore WORKDIR from WORKDIR/backup-before

Example:
    python tools/repair_memory_sources.py rehearse \
      --living-db AstrBot/data/plugin_data/astrbot_plugin_livingmemory/livingmemory.db \
      --conversations-db AstrBot/data/plugin_data/astrbot_plugin_livingmemory/conversations.db \
      --workdir tmp-memory-rehearsal \
      --memory-id 20 --memory-id 21 \
      --start-id 391 --end-id 412
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sqlite3
import sys
import time
from pathlib import Path
from typing import Any

MANIFEST = "rehearsal-manifest.json"
WORK_LIVING = "livingmemory.db"
WORK_CONVERSATIONS = "conversations.db"
BACKUP_DIR = "backup-before"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _backup_sqlite(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    source_conn = sqlite3.connect(f"file:{source}?mode=ro", uri=True)
    destination_conn = sqlite3.connect(destination)
    try:
        source_conn.backup(destination_conn)
    finally:
        destination_conn.close()
        source_conn.close()


def _remove_sqlite_sidecars(path: Path) -> None:
    for suffix in ("-wal", "-shm", "-journal"):
        sidecar = Path(str(path) + suffix)
        try:
            sidecar.unlink()
        except FileNotFoundError:
            pass


def _restore_file(backup: Path, target: Path) -> None:
    _remove_sqlite_sidecars(target)
    shutil.copy2(backup, target)


def _integrity_check(path: Path) -> str:
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        row = conn.execute("PRAGMA integrity_check").fetchone()
        return str(row[0] if row else "missing")
    finally:
        conn.close()


def _read_messages(path: Path, start_id: int, end_id: int) -> list[dict[str, Any]]:
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            """
            SELECT id, session_id, role, content, sender_id, sender_name,
                   group_id, platform, timestamp, metadata
            FROM messages
            WHERE id BETWEEN ? AND ?
            ORDER BY id
            """,
            (start_id, end_id),
        ).fetchall()
    finally:
        conn.close()
    if not rows:
        raise ValueError(f"no messages in range {start_id}-{end_id}")
    result = []
    for row in rows:
        metadata = row["metadata"]
        try:
            metadata = json.loads(metadata) if isinstance(metadata, str) else metadata
        except json.JSONDecodeError:
            metadata = {}
        if not isinstance(metadata, dict):
            metadata = {}
        result.append(
            {
                "id": int(row["id"]),
                "session_id": str(row["session_id"] or ""),
                "role": str(row["role"] or "user"),
                "content": str(row["content"] or ""),
                "sender_id": str(row["sender_id"] or "unknown"),
                "sender_name": row["sender_name"],
                "group_id": row["group_id"],
                "platform": row["platform"],
                "timestamp": float(row["timestamp"] or 0.0),
                "metadata": {"is_bot_message": bool(metadata.get("is_bot_message", False))},
            }
        )
    return result


def _source_json(messages: list[dict[str, Any]]) -> str:
    return json.dumps(messages, ensure_ascii=False, separators=(", ", ": "))


def _memory_window(path: Path, memory_ids: list[int]) -> dict[int, str]:
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        out: dict[int, str] = {}
        for memory_id in memory_ids:
            row = conn.execute(
                "SELECT source_json FROM memory_sources WHERE memory_id = ?",
                (memory_id,),
            ).fetchone()
            out[memory_id] = str(row["source_json"]) if row else ""
        return out
    finally:
        conn.close()


def _apply(path: Path, sources: dict[int, str]) -> None:
    conn = sqlite3.connect(path)
    try:
        now = time.time()
        conn.execute("BEGIN IMMEDIATE")
        for memory_id, source_json in sources.items():
            existing = conn.execute(
                "SELECT created_at FROM memory_sources WHERE memory_id = ?",
                (memory_id,),
            ).fetchone()
            created_at = float(existing[0]) if existing else now
            conn.execute(
                """
                INSERT INTO memory_sources (memory_id, source_json, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(memory_id) DO UPDATE SET
                    source_json = excluded.source_json,
                    updated_at = excluded.updated_at
                """,
                (memory_id, source_json, created_at, now),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _verify(path: Path, memory_ids: list[int], start_id: int, end_id: int) -> dict[str, Any]:
    integrity = _integrity_check(path)
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        result: dict[str, Any] = {
            "integrity_check": integrity,
            "sources": {},
        }
        for memory_id in memory_ids:
            row = conn.execute(
                "SELECT source_json, length(source_json) AS size FROM memory_sources WHERE memory_id = ?",
                (memory_id,),
            ).fetchone()
            if row is None:
                result["sources"][memory_id] = {"present": False}
                continue
            messages = json.loads(row["source_json"])
            ids = [int(item.get("id", 0)) for item in messages]
            result["sources"][memory_id] = {
                "present": True,
                "size": int(row["size"]),
                "message_count": len(messages),
                "first_id": min(ids) if ids else None,
                "last_id": max(ids) if ids else None,
                "range_ok": bool(ids) and min(ids) >= start_id and max(ids) <= end_id,
            }
        return result
    finally:
        conn.close()


def _prepare_workdir(args: argparse.Namespace) -> Path:
    workdir = args.workdir.resolve()
    workdir.mkdir(parents=True, exist_ok=True)
    living = workdir / WORK_LIVING
    conversations = workdir / WORK_CONVERSATIONS
    if not living.exists():
        _backup_sqlite(args.living_db.resolve(), living)
    if not conversations.exists():
        _backup_sqlite(args.conversations_db.resolve(), conversations)
    backup = workdir / BACKUP_DIR
    backup.mkdir(parents=True, exist_ok=True)
    for path in (living, conversations):
        backup_path = backup / path.name
        if not backup_path.exists():
            shutil.copy2(path, backup_path)
    return workdir


def _report(workdir: Path, memory_ids: list[int], start_id: int, end_id: int) -> dict[str, Any]:
    living = workdir / WORK_LIVING
    conversations = workdir / WORK_CONVERSATIONS
    messages = _read_messages(conversations, start_id, end_id)
    source_json = _source_json(messages)
    existing = _memory_window(living, memory_ids)
    return {
        "start_id": start_id,
        "end_id": end_id,
        "message_count": len(messages),
        "source_size": len(source_json.encode("utf-8")),
        "existing": {str(key): bool(value) for key, value in existing.items()},
    }


def _rehearse(args: argparse.Namespace) -> int:
    workdir = _prepare_workdir(args)
    manifest_path = workdir / MANIFEST
    manifest: dict[str, Any] = {
        "created_at": time.time(),
        "source_living_sha256": _sha256(args.living_db.resolve()),
        "source_conversations_sha256": _sha256(args.conversations_db.resolve()),
        "living_sha256_before": _sha256(workdir / WORK_LIVING),
        "conversations_sha256_before": _sha256(workdir / WORK_CONVERSATIONS),
    }
    dry_run = _report(workdir, args.memory_id, args.start_id, args.end_id)
    manifest["dry_run"] = dry_run

    messages = _read_messages(workdir / WORK_CONVERSATIONS, args.start_id, args.end_id)
    sources = {memory_id: _source_json(messages) for memory_id in args.memory_id}
    existing = _memory_window(workdir / WORK_LIVING, args.memory_id)
    if not args.allow_existing and any(existing.values()):
        raise SystemExit("refusing to overwrite an existing memory_sources row; use --allow-existing")
    _apply(workdir / WORK_LIVING, sources)
    after_apply = _verify(workdir / WORK_LIVING, args.memory_id, args.start_id, args.end_id)
    manifest["after_apply"] = after_apply

    _restore_file(workdir / BACKUP_DIR / WORK_LIVING, workdir / WORK_LIVING)
    _restore_file(workdir / BACKUP_DIR / WORK_CONVERSATIONS, workdir / WORK_CONVERSATIONS)
    after_rollback = _verify(workdir / WORK_LIVING, args.memory_id, args.start_id, args.end_id)
    manifest["after_rollback"] = after_rollback
    manifest["living_sha256_after_rollback"] = _sha256(workdir / WORK_LIVING)
    manifest["conversations_sha256_after_rollback"] = _sha256(workdir / WORK_CONVERSATIONS)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    if manifest["living_sha256_before"] != manifest["living_sha256_after_rollback"]:
        raise SystemExit("rollback hash mismatch")
    if after_apply.get("integrity_check") != "ok" or after_rollback.get("integrity_check") != "ok":
        raise SystemExit("integrity_check failed")
    return 0


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("rehearse", "dry-run", "apply", "verify", "rollback"))
    parser.add_argument("--living-db", type=Path, required=True)
    parser.add_argument("--conversations-db", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--memory-id", type=int, action="append", required=True)
    parser.add_argument("--start-id", type=int, required=True)
    parser.add_argument("--end-id", type=int, required=True)
    parser.add_argument("--allow-existing", action="store_true")
    return parser


def main() -> int:
    args = _parser().parse_args()
    if args.mode == "rehearse":
        return _rehearse(args)
    workdir = _prepare_workdir(args)
    living = workdir / WORK_LIVING
    if args.mode == "dry-run":
        print(json.dumps(_report(workdir, args.memory_id, args.start_id, args.end_id), ensure_ascii=False, indent=2))
        return 0
    if args.mode == "verify":
        print(json.dumps(_verify(living, args.memory_id, args.start_id, args.end_id), ensure_ascii=False, indent=2))
        return 0
    if args.mode == "rollback":
        _restore_file(workdir / BACKUP_DIR / WORK_LIVING, living)
        _restore_file(workdir / BACKUP_DIR / WORK_CONVERSATIONS, workdir / WORK_CONVERSATIONS)
        print(json.dumps(_verify(living, args.memory_id, args.start_id, args.end_id), ensure_ascii=False, indent=2))
        return 0
    messages = _read_messages(workdir / WORK_CONVERSATIONS, args.start_id, args.end_id)
    sources = {memory_id: _source_json(messages) for memory_id in args.memory_id}
    existing = _memory_window(living, args.memory_id)
    if not args.allow_existing and any(existing.values()):
        raise SystemExit("refusing to overwrite an existing memory_sources row; use --allow-existing")
    _apply(living, sources)
    print(json.dumps(_verify(living, args.memory_id, args.start_id, args.end_id), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
