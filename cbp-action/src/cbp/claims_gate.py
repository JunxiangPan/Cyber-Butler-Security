"""Generic release-claim reconciliation gate."""
from __future__ import annotations

RULE_ID = "CBP-CLM-001"

import json
import re

from .config import GateConfig

TOKEN = re.compile(r"(?m)^QUALITY_COUNTS:\s*(\d+)/(\d+)\s*$")
HANDWRITTEN = re.compile(r"(?<![\w/])26\s*/\s*26(?![\w/])")


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Match release-note quality claims to the machine manifest."""
    if not cfg.claims_manifest or not cfg.claims_notes:
        return False, "claims_manifest and claims_notes must be configured"
    manifest = cfg.path(cfg.claims_manifest)
    notes = cfg.path(cfg.claims_notes)
    if not manifest.is_file():
        return False, (
            "quality-manifest.json missing. "
            "Run `python tools/dogfood_manifest.py --root .` first to generate a local manifest."
        )
    if not notes.is_file():
        return False, "release notes missing. Run the dogfood command first to generate them."
    data = json.loads(manifest.read_text(encoding="utf-8"))
    counts = data.get("counts", {})
    expected = f"{counts.get('passed', -1)}/{counts.get('total', -1)}"
    text = notes.read_text(encoding="utf-8")
    tokens = TOKEN.findall(text)
    if len(tokens) != 1:
        return False, "release notes need exactly one QUALITY_COUNTS line"
    actual = f"{tokens[0][0]}/{tokens[0][1]}"
    if actual != expected:
        return False, f"notes {actual} != manifest {expected}"
    if HANDWRITTEN.search(text):
        return False, "handwritten 26/26 claim is forbidden"
    if data.get("profile") == "release" and int(counts.get("passed", 0)) != 26:
        return False, "release profile is not 26/26"
    return True, f"claims={actual}"
