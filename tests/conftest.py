"""Shared test setup for the public release.

The tests intentionally avoid importing AstrBot, pywin32, or the live
deployment. They exercise the pure security functions and load the Security
Gate source with minimal AstrBot API stubs.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT))
