#!/usr/bin/env python3
"""Merge a real VM ACCEPTANCE_PROOF into the final QA report.

This tool does not inspect PROOF_SHA256: that field is written by the repack
step because the proof does not exist yet when the pre-VM build is made.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_QA = ROOT / "FINAL_QA_REPORT.md"
WHITELIST = ("Q05", "Q06", "Q07", "Q08", "Q09", "Q10", "Q11", "Q13", "Q14", "Q15", "Q16", "Q17")
BLACKLIST: tuple[str, ...] = ()
EXPECTED_SKIPPED = 12
NONCE_RE = re.compile(r"(?m)^-\s*Nonce:\s*(\S+)\s*$")
START_RE = re.compile(r"Acceptance script SHA256 \(start\):\s*([0-9A-Fa-f]{64})")
END_RE = re.compile(r"Acceptance script SHA256 \(end\):\s*([0-9A-Fa-f]{64})")


class MergeError(RuntimeError):
    """Raised when proof or QA preconditions fail."""


def verify_proof(path: Path) -> str:
    """Validate proof contents independent of BUILD_REPORT and return Nonce."""
    if not path.is_file() or path.stat().st_size == 0:
        raise MergeError("ACCEPTANCE_PROOF.md is missing or empty")
    text = path.read_text(encoding="utf-8-sig")
    if "Overall: PASS" not in text:
        raise MergeError("ACCEPTANCE_PROOF.md is not Overall: PASS")
    for marker in ("negative_403=True", "negative_path=True", "script_immutable=True"):
        if marker not in text:
            raise MergeError("ACCEPTANCE_PROOF.md missing " + marker)
    nonce = NONCE_RE.search(text)
    if not nonce or not nonce.group(1).strip():
        raise MergeError("ACCEPTANCE_PROOF.md Nonce is missing or empty")
    starts = START_RE.findall(text)
    ends = END_RE.findall(text)
    if not starts or not ends:
        raise MergeError("ACCEPTANCE_PROOF.md missing script SHA256 start/end")
    if starts[-1].upper() != ends[-1].upper():
        raise MergeError("ACCEPTANCE_PROOF.md script SHA256 changed while running")
    print("PROOF_VERIFIED")
    print("PROOF_SHA256=" + hashlib.sha256(path.read_bytes()).hexdigest().upper())
    return nonce.group(1)


def _rows(lines: list[str]) -> list[tuple[int, list[str]]]:
    """Return (line index, four cells) for QA table rows."""
    result: list[tuple[int, list[str]]] = []
    for index, line in enumerate(lines):
        if not line.strip().startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) == 4 and cells[0].startswith("Q"):
            result.append((index, cells))
    return result


def merge(proof_path: Path, expected_nonce: str, qa_path: Path) -> None:
    """Validate all preconditions, then mutate QA from BLOCKED to PASS."""
    verify_proof(proof_path)
    proof_text = proof_path.read_text(encoding="utf-8-sig")
    proof_match = NONCE_RE.search(proof_text)
    if not proof_match:
        raise MergeError("ACCEPTANCE_PROOF.md Nonce is missing or empty")
    proof_nonce = proof_match.group(1).strip()
    if proof_nonce != expected_nonce:
        raise MergeError("PROOF Nonce does not match --nonce")
    if not qa_path.is_file():
        raise MergeError("FINAL_QA_REPORT.md is missing")
    original = qa_path.read_bytes()
    text = qa_path.read_text(encoding="utf-8-sig")
    qa_nonce = NONCE_RE.search(text)
    if not qa_nonce or qa_nonce.group(1).strip() != proof_nonce:
        raise MergeError("PROOF Nonce does not match FINAL_QA_REPORT.md Nonce")
    if "Overall: **BLOCKED**" not in text:
        raise MergeError("FINAL_QA_REPORT.md is not BLOCKED; refusing duplicate merge")
    lines = text.splitlines()
    rows = _rows(lines)
    skipped = [cells[0] for _, cells in rows if cells[-1] == "skipped"]
    if len(skipped) != EXPECTED_SKIPPED:
        raise MergeError(f"FINAL_QA_REPORT.md has {len(skipped)} skipped rows, expected {EXPECTED_SKIPPED}")
    for item in BLACKLIST:
        row = next((cells for _, cells in rows if cells[0] == item), None)
        if row is None or row[-1] != "skipped":
            raise MergeError(f"{item} is not skipped; refusing merge")
    changed = []
    for index, cells in rows:
        if cells[0] not in WHITELIST:
            continue
        line = lines[index]
        new_line = line.replace("| skipped |", "| passed |")
        if new_line == line:
            raise MergeError(f"{cells[0]} skipped cell could not be updated")
        lines[index] = new_line
        changed.append(cells[0])
    if len(changed) != len(WHITELIST):
        raise MergeError(f"expected {len(WHITELIST)} whitelist changes, got {len(changed)}")
    text = "\n".join(lines).replace("Overall: **BLOCKED**", "Overall: **PASS**", 1) + "\n"
    backup = qa_path.with_name(qa_path.name + ".pre-vm-merge")
    if backup.exists():
        raise MergeError("backup already exists: " + str(backup))
    shutil.copy2(qa_path, backup)
    qa_path.write_text(text, encoding="utf-8")
    if qa_path.read_bytes() == original:
        raise MergeError("QA report was not changed")
    print("MERGED")
    print("CHANGED=" + ",".join(changed))
    print("PROOF_NONCE=" + proof_nonce)
    print("BACKUP=" + str(backup))
    print("BUILD_REPORT_UNTOUCHED=true")


def main() -> int:
    """Run verify-proof or the merge command."""
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("verify-proof", "merge"))
    parser.add_argument("--proof", required=True)
    parser.add_argument("--nonce", default="")
    parser.add_argument("--qa-report", default=str(DEFAULT_QA))
    args = parser.parse_args()
    try:
        if args.command == "verify-proof":
            verify_proof(Path(args.proof))
            return 0
        if not args.nonce:
            raise MergeError("merge requires --nonce")
        merge(Path(args.proof), args.nonce, Path(args.qa_report))
        return 0
    except MergeError as exc:
        print("REFUSING MERGE: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
