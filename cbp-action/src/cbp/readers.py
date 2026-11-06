"""Small configurable evidence-reader registry.

The registry deliberately does not import third-party code. A file type is
described by suffixes and an encoding; language-specific rules can select a
named reader explicitly or let the suffix pick the default text reader.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

DEFAULT_MAX_BYTES = 2_000_000


@dataclass(frozen=True)
class Reader:
    name: str
    suffixes: tuple[str, ...]
    encoding: str = "utf-8"
    max_bytes: int = DEFAULT_MAX_BYTES


def configured_readers(cfg) -> dict[str, Reader]:
    raw = getattr(cfg, "evidence_readers", None) or {}
    readers: dict[str, Reader] = {}
    if not isinstance(raw, dict):
        return readers
    for name, spec in raw.items():
        if not isinstance(spec, dict):
            continue
        suffixes = spec.get("suffixes", [])
        if isinstance(suffixes, str):
            suffixes = [suffixes]
        if not isinstance(suffixes, list):
            continue
        readers[str(name)] = Reader(
            name=str(name),
            suffixes=tuple(str(item).lower() for item in suffixes if str(item)),
            encoding=str(spec.get("encoding", "utf-8")),
            max_bytes=int(spec.get("max_bytes", DEFAULT_MAX_BYTES)),
        )
    return readers


def resolve(cfg, path: Path, explicit: str = "") -> Reader:
    readers = configured_readers(cfg)
    if explicit:
        if explicit not in readers:
            raise ValueError(f"reader not configured: {explicit}")
        return readers[explicit]
    suffix = path.suffix.lower()
    for reader in readers.values():
        if suffix in reader.suffixes:
            return reader
    return Reader("text", (suffix,), "utf-8")


def read(path: Path, reader: Reader) -> tuple[str, str]:
    if path.stat().st_size > reader.max_bytes:
        return "", f"file exceeds reader limit {reader.max_bytes} bytes"
    try:
        return path.read_text(encoding=reader.encoding), ""
    except (OSError, UnicodeDecodeError) as exc:
        return "", str(exc)
