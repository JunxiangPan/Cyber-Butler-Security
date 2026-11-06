"""Baseline fingerprints for pre-existing findings."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

SCHEMA = "cbp-baseline/v1"


def fingerprint(gate: str, line: str) -> str:
    return hashlib.sha256((gate + "\0" + line.strip()).encode("utf-8")).hexdigest()


def load(path: Path | str | None) -> set[str]:
    if not path:
        return set()
    p = Path(path)
    if not p.is_file():
        return set()
    data = json.loads(p.read_text(encoding="utf-8"))
    return {str(item["fingerprint"]) for item in data.get("entries", []) if isinstance(item, dict) and item.get("fingerprint")}


def write(path: Path, gate: str, lines: list[str]) -> int:
    entries = [{"gate": gate, "fingerprint": fingerprint(gate, line), "line": line} for line in lines]
    data = {"schema": SCHEMA, "version": 1, "entries": entries}
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return len(entries)


def filter_lines(cfg, gate: str, lines: list[str]) -> list[str]:
    configured = getattr(cfg, "baseline", "")
    path = cfg.path(configured) if configured else cfg.root / "cbp-baseline.json"
    allowed = load(path)
    return [line for line in lines if fingerprint(gate, line) not in allowed]


def write_entries(path: Path, entries: list[tuple[str, str]]) -> int:
    data = {
        "schema": SCHEMA,
        "version": 1,
        "entries": [
            {"gate": gate, "fingerprint": fingerprint(gate, line), "line": line}
            for gate, line in entries
        ],
    }
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + chr(10), encoding="utf-8")
    return len(data["entries"])
