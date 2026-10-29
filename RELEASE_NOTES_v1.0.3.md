# v1.0.3 — Media Egress, Manifest and Backoff Hardening

**Release date:** 2026-10-29  
**License:** AGPL-3.0  
**Scope:** emergency white-box audit response

> [!WARNING]
> This project still depends on unofficial QQ protocol clients such as SnowLuma. Use a test account only. Account restriction, suspension, or permanent bans remain possible. See [SECURITY.md](SECURITY.md) and [README.md](README.md).

## Summary

V1.0.3 closes six logic gaps found in the V1.0.2 review:

- media components could bypass the file egress gate;
- TOTP prompts showed only a basename;
- Broker `send` had no shared-folder path restriction;
- owner lookup failure was fail-open;
- TOTP attempt limits could be lost when a pending request disappeared;
- the `/lockapi` state file lived under the read-only `tools/` tree.

It also removes a leaked QQ identifier from the deployment guide and trims internal operational history.

## P0 Fixes

### F13 — leaked QQ identifier removed

The three occurrences in `docs/使用说明.md` were replaced with `YOUR_QQ_ID`.  
A project-wide scan for the known leaked identifiers now returns zero matches.

### F1 — all media components enter the TOTP path

`message_tools.py` now collects:

```text
Comp.File
Comp.Image
Comp.Record
Comp.Video
```

Every local path is passed through `_totp_path_risk` and the complete send manifest. Changing a `.txt` to `.jpg` no longer skips the guard.

### F2 — full-path TOTP prompt

The Broker prompt now shows:

- the complete absolute path;
- size;
- full SHA-256;
- `[OUTSIDE SHARED]` when a path is outside the shared folder.

### F3 — `send` is shared-folder only

`action=send` now rejects:

- URLs;
- any manifest entry outside the shared folder.

Response: `403 send manifest contains a path outside the shared folder`.

## P1 Fixes

### F4 — owner lookup fail-closed

If `win32security` returns an empty owner, the file is treated as risky and forced through TOTP. It is no longer treated as trusted.

### F5 — global exponential TOTP backoff

The per-request `attempts` counter is backed by a process-global failure ledger:

- 5 failures → 300 seconds;
- subsequent failures → 600s, 1200s, 2400s… capped at 24 hours;
- pending request expiry or clearing does not erase the global counter;
- a successful verification resets the global counter.

### F9 — lock-state file moved

`/锁定API` and `/解锁API` now write:

```text
AstrBot/data/security-gate-api-lock.json
```

instead of the read-only `tools/` directory.

## P2 Fixes

### Expanded tests: 17 passed

New regression coverage:

- `tests/test_broker_manifest.py`
  - send without manifest → 409;
  - send outside shared folder → 403;
  - manifest tampered before approval → 409;
  - prompt contains full path and outside marker.
- `tests/test_media_bypass.py`
  - Image/Record/Video are collected with File;
  - owner lookup failure is fail-closed.
- existing TOTP, ACL, injection and lockout tests.

```text
17 passed in 0.46s
```

### Documentation reduced

`docs/使用说明.md` no longer includes detailed PID, port-probing and timestamped test-run diaries. Operational troubleshooting details are kept in private logs; the public guide retains architecture, setup, TOTP and security boundaries.

## Upgrade Notes

- Copy the updated `message_tools.py` overlay and `broker.py`.
- Restart AstrBot and the Broker after deployment.
- Shared-folder-only `send` is intentional: media generated in other directories will be rejected unless moved into the shared folder.
- The `Game Mode Watchdog` silent VBS launcher and state recovery from v1.0.2 remain included.

## Known Limitations

- TOTP cannot prove the human identity behind a compromised phone/authenticator.
- The final hash check still leaves a narrow TOCTOU window before the message is sent.
- Plain text is not fully mediated; code-execution tools are removed from QQ private requests, but a different agent path or plugin could re-add them.
- Media/voice/video and Shell execution do not have an equivalent secondary confirmation beyond the path/manifest guard.
- Unofficial QQ protocol account-ban risk remains.

## Verification

```bash
python -m pip install -r requirements-dev.txt
python -m pytest -q
```

Expected:

```text
17 passed
```

## Lock/Unlock Provider-Switch Fix

The V1.0.3 lock/unlock command exposed a regression: `security_gate._switch_provider` called synchronous `requests.patch` from inside an async handler. That blocked AstrBot's event loop long enough for the API call to time out.

Fixes:

- the HTTP request now runs in `asyncio.to_thread`;
- non-2xx responses log status and response body;
- provider IDs are named constants (`local_qwen36`, `deepseek`);
- the state file remains under `AstrBot/data/`.

Live validation performed:

- direct internal API `PATCH /api/v1/sessions/provider` → `status=ok` for deepseek and local_qwen36;
- plugin lock/unlock flow → no timeout, state file written and cleared;
- final private-session provider restored to `local_qwen36`;
- AstrBot `6185` and Broker `18090` both `200`.
