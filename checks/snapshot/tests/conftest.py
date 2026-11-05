"""Shared test setup for the public release.

The tests intentionally avoid importing AgentRuntime, pywin32, or the live
deployment. They exercise the pure security functions and load the Security
Gate source with minimal AgentRuntime API stubs.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("CBS_DISABLE_JITTER", "1")
os.environ.setdefault("CBS_DISABLE_ACL", "1")
os.environ.setdefault("CBS_AUDIT_HMAC_KEY", "00" * 32)
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT))
