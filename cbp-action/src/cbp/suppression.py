"""Generic inline suppression for file/line gate findings."""
from __future__ import annotations

import re
from pathlib import Path

MARKER = re.compile(r"cbp:\s*ignore(?:\s*=\s*(CBP-[A-Z]+-\d{3}))?", re.IGNORECASE)
FINDING = re.compile(r"^(?P<path>[^:\n]+):(?P<line>\d+):")


def filter_text(root: Path, text: str) -> str:
    """Remove findings whose source line carries an inline cbp: ignore marker."""
    kept: list[str] = []
    for finding in text.splitlines():
        match = FINDING.match(finding)
        if not match:
            kept.append(finding)
            continue
        source = (root / match.group("path")).resolve()
        try:
            source.relative_to(root.resolve())
        except ValueError:
            kept.append(finding)
            continue
        try:
            line = source.read_text(encoding="utf-8", errors="replace").splitlines()[int(match.group("line")) - 1]
        except (OSError, IndexError):
            kept.append(finding)
            continue
        marker = MARKER.search(line)
        if marker:
            required = marker.group(1)
            if not required or required.upper() in finding.upper():
                continue
        kept.append(finding)
    return "\n".join(kept)
