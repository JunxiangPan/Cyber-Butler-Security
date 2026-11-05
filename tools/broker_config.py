"""Configuration constants for the local broker service.

Path and timeout values are environment-derived so the same code runs in
production and in the isolated pytest fixtures.
"""
from __future__ import annotations

import os
import tempfile
from pathlib import Path

TEST_MODE = os.environ.get("CBS_TEST_MODE") == "1"
_SOURCE_ROOT = Path(__file__).resolve().parents[1]
ROOT = Path(os.environ.get("CBS_TEST_ROOT", str(_SOURCE_ROOT))) if TEST_MODE else Path(os.environ.get("CBS_ROOT", str(_SOURCE_ROOT)))
BROKER = ROOT / "tools" / "broker"
QUARANTINE = BROKER / "trash_staging"
STAGING = BROKER / "staging"
TOTP_VAULT = ROOT / "tools" / "totp-vault"
SECRET_FILE = TOTP_VAULT / "totp_secret.dpapi"
RECOVERY_FILE = TOTP_VAULT / "recovery_hashes.json"
LEGACY_SECRET_FILE = ROOT / "tools" / "totp_secret.dpapi"
LEGACY_RECOVERY_FILE = ROOT / "tools" / "totp_recovery.json"
TOKEN_FILE = ROOT / "tools" / "broker_token.txt"
LOG = (Path(tempfile.gettempdir()) / "cyberbutler-test-broker.log") if TEST_MODE else (ROOT / "tools" / "totp_broker.log")
AUDIT = ROOT / "tools" / "totp_broker_audit.jsonl"
BROKER_CONFIG = ROOT / "tools" / "broker_config.json"
HOST = "127.0.0.1"
PORT = int(os.environ.get("CBS_TEST_PORT", "18090")) if TEST_MODE else 18090
ALLOWED_HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}
TIMEOUT_SECONDS = 300
REQUEST_RATE_LIMIT_SECONDS = 1.0
REQUEST_BURST = 3
REQUEST_REFILL_SECONDS = 30.0
DENY_JITTER_MIN = 0.05
DENY_JITTER_MAX = 0.25
