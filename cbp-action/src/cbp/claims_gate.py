"""Generic release-claim reconciliation gate."""
from __future__ import annotations

RULE_ID = "CBP-CLM-001"

import json
import re

from .config import GateConfig

TOKEN = re.compile(r"(?m)^QUALITY_COUNTS:\s*(\d+)/(\d+)\s*$")
GATE_CLAIM = re.compile(r"\b(?:all|across|through)\s+([A-Za-z]+|\d+)\s+gates?\b", re.IGNORECASE)
WORDS = {
    word: number
    for number, word in enumerate(
        ("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten")
    )
}


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
    total = int(counts.get("total", -1))
    gate_claim = GATE_CLAIM.search(text)
    if gate_claim:
        token = gate_claim.group(1).lower()
        number = int(token) if token.isdigit() else WORDS.get(token)
        if number is None:
            return False, f"unknown gate count claim: {gate_claim.group(0)}"
        if number != total:
            return False, f"notes claim {token} gates but manifest has {total}"
    return True, f"claims={actual}"
