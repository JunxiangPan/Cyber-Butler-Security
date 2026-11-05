"""Mutable state shared by the broker service layers.

Keeping this state in one module avoids circular imports: policy and service
code read/write the same locks and maps through broker_state.
"""
from __future__ import annotations

import threading

_lock = threading.Lock()
_replay_lock = threading.Lock()
_request_rate_lock = threading.Lock()
_last_request_at = 0.0
_request_buckets: dict[str, tuple[float, float]] = {}
_used_totp: dict[str, float] = {}
_verify_locked_until = 0.0
_global_failures = 0
_global_lock_until = 0.0
_pending: dict | None = None

_bypass_lock = threading.Lock()
_bypass_tokens: dict[str, dict] = {}
_approval_lock = threading.Lock()
_approval_states: dict[str, dict] = {}
_scoped_lock = threading.Lock()
_scoped_tokens: dict[str, dict] = {}
_retained_lock = threading.Lock()
_retained_snapshots: dict[str, dict] = {}

TOTP_REPLAY_TTL = 120
TOTP_MAX_ATTEMPTS = 5
VERIFY_LOCK_SECONDS = 300
GLOBAL_LOCK_BASE_SECONDS = 300
GLOBAL_LOCK_MAX_SECONDS = 86400
BYPASS_TTL_SECONDS = 30
APPROVAL_STATE_TTL_SECONDS = 600
SCOPED_TTL_SECONDS = 1800
SCOPED_MAX_MINUTES = 30
