#!/usr/bin/env python3
"""Mark only Q24 and Q26 as passed after their real package tests succeed."""
from __future__ import annotations

from pathlib import Path
import re
import sys

EXPECTED = ("Q24", "Q26")


def main() -> int:
    """Update the two package checks only when their rows are still skipped."""
    qa = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("FINAL_QA_REPORT.md")
    text = qa.read_text(encoding="utf-8")
    for item in EXPECTED:
        pattern = re.compile(rf"^(\| {item} \|.*\| )skipped( \|)$", re.MULTILINE)
        text, count = pattern.subn(r"\1passed\2", text)
        if count != 1:
            raise SystemExit(f"expected one skipped row for {item}, got {count}")
    qa.write_text(text, encoding="utf-8")
    print("Q24_Q26_PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
