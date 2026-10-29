# v1.0.6 — Egress Approval Repair and Event-Loop Hardening

## P0 — URL / outside-shared sends are approval-capable

The overlay already classified remote URLs and files outside the shared folder as risky and called the TOTP broker. The broker then rejected the same manifest with `403`, making the approval impossible.

Changed:

- `tools/broker.py` now issues a TOTP challenge for the complete send manifest, including:
  - `kind: url`
  - local files outside the shared folder
- The challenge prompt keeps the full path / URL and the `[OUTSIDE SHARED]` marker.
- The manifest is still re-hashed at `/verify`; tampering returns `409`.
- No shared-folder restriction was removed for delete/overwrite.

Tests added:

- outside-shared send reaches the challenge path;
- URL send reaches the challenge path;
- overlay source contract test confirms the overlay routes both cases to `_totp_request_send`.

## P1 — Event-loop and request-rate hardening

- `plugins/astrbot_plugin_totp_broker/main.py` now runs blocking `requests` calls through `asyncio.to_thread`.
- `tools/broker.py` rate-limits `/request` to one request per second per Broker process.

## Documentation corrections

- `SECURITY.md` now states that the DPAPI secret uses `CRYPTPROTECT_LOCAL_MACHINE` (machine scope); the vault ACL is the effective boundary, not user-bound encryption.
- `SECURITY.md` now states that the replay cache, pending request, verification lock, and global backoff are in memory and reset on Broker restart.
- `tools/setup_totp.py` documents the machine-scope flag.

## Verification

```text
20 passed
```

## Remaining reported items (not silently fixed)

- Sanitization still contains deployment literals such as `qq_sujinyan`, `苏瑾言`, and `大肥鱼专用文件夹`; extend the sanitizer or replace them in a separate release.
- The owner-input rule still forwards any 6-digit number to `/verify`; a prefixed challenge format is a separate UX/security change.
- Outstanding test count is now 20 because the P0 regression tests were added.
