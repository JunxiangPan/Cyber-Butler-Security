# v1.3.2 — Security hardening: signed updates, email approval, fail-closed dashboard modules

## Phase 1 — trust boundary and release integrity

- **Broker approval binding.** `delete` / `overwrite` prompts now include the
  full path, type, size and SHA-256. The pending action freezes the target and
  source summaries; `/verify` recomputes them and returns `409` if a file
  changed before approval.
- **RSA-3072 release signing.** `sign_release.py` signs the exact bytes of
  `update-manifest.json`; `verify_release.py` verifies it against the pinned
  `tools/update_pubkey.pem`. `update_merge.ps1` refuses a package when the
  signature is missing or invalid. The private key lives in
  `C:\ProgramData\CyberButler\keys` with an ACL limited to SYSTEM and
  Administrators.
- **Bootstrap.** v1.3.1 cannot verify signatures; v1.3.2 is a one-time manual
  install. v1.3.3 and later are verified automatically.
- **Dashboard modules fail closed.** Only the three official modules are
  loaded; their `logic.ps1` SHA-256 is pinned. Any external module is refused
  before dot-sourcing, with a red security banner. This is deliberately
  stricter than a static scan: the scan is only a diagnostic, not a sandbox.
- **Log redaction.** `Copy Error Log` now redacts `sk-…`, `Authorization:
  Bearer …`, `api_key=/token=/secret=` and Windows drive paths without
  corrupting `https://`.

## Phase 2 — SMTP/IMAP out-of-band approval

- The broker sends approval mail directly through `smtp.163.com:465` (SSL); the
  SMTP/IMAP credentials are stored as a **DPAPI machine-scope** blob in
  `C:\ProgramData\CyberButler\email_secret.json` (SYSTEM/Administrators only).
- IMAP polling reads INBOX, Sent and Junk, including 163's modified-UTF-7
  folder names (`&XfJT0ZAB-`), adds the 163 `ID` handshake, parses plain or
  HTML bodies, and cuts at `------------------ 原始邮件 ------------------`
  before reading the first `APPROVE #… TOTP 123456` line.
- The sender must exactly equal the configured `allowed_sender`; the challenge
  must match the pending request; the TOTP must be valid; target/source hashes
  are rechecked; the approval is one-time and expires after 5 minutes.
- `/verify` refuses an email-mode pending, so AstrBot cannot approve it.

### Dual channel

`tools/broker_config.json`:

```json
{ "approval_channel": "qq" }
```

Switch to `"email"` and restart the broker to send delete/overwrite approvals
by mail. The package ships with `qq` as the safe default; the local install is
set to `email`. `send` actions remain on the QQ/TOTP path in this release
because their tool call is synchronous; that is documented as a residual.

## Verified

```text
pytest                      43 passed
privacy scan                OK
email end-to-end            APPROVE #583F accepted; email_e2e_test7.txt moved to quarantine
broker                      /health 200
RSA sign/verify             SIG_OK / VALID
dashboard modules           3 official loaded; external module rejected with red banner
```

## Notes

- Email self-send: 163 may store the owner's reply in Sent rather than INBOX;
  the poller scans both.
- A reply must contain a six-digit TOTP; `TOTP +动态码` is not accepted.
- The broker signature check requires `tools/verify_release.py` and
  `tools/update_pubkey.pem`; both are included.

## CI fix (this build)

- Removed `tools/send_email_test.py` (a Windows-only DPAPI helper that matched
  pytest's `*_test.py` pattern and failed Linux collection with
  `ModuleNotFoundError: win32crypt`). The SMTP test uses
  `tools/send_email_stdin.py`, which is standard-library only.
- Added `pytest.ini` with `testpaths = tests` and `python_files = test_*.py`,
  so `pytest -q` never collects tools/ or platform-specific scripts.
