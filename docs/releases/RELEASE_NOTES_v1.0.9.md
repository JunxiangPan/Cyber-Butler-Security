# v1.0.9 — Dashboard and Security Hardening

## Added

- `tools/cyber_butler_dashboard.ps1`: read-only WPF dashboard with four tabs.
- `tools/dashboard_core.ps1`: port, GPU, provider, audit, game-list and persona
  readers.
- `tools/cyber_butler_dashboard.vbs`: no-console launcher.
- `tools/create_dashboard_shortcut.ps1`: desktop shortcut creator.

## Phase 1 scope

Phase 1/2 includes read-only monitoring and the first interactive actions:

- status cards for AstrBot (6185), Broker (18090), SnowLuma (5099);
- GPU memory bar;
- configured provider display;
- last ten TOTP audit records;
- read-only System Prompt;
- merged auto/manual game whitelist and built-in ignore list;
- UAC-based restart, VRAM release, FUSE, persona reload, conversation clear,
  DPAPI API-key save and game-list management.

## Security fixes

- TOTP setup now aborts when `icacls` fails and creates explicit Deny Read for
  `AstrBot_User` on the DPAPI secret and recovery store.
- `verify_broker_acl.ps1` verifies those explicit denies and the Broker refuses
  to start when they are absent.
- QQ network I/O moved outside the Broker pending-state lock.
- Added a release privacy scanner and CI gate for private identifiers.
- README test count and SECURITY platform-prefix warning updated.

## Security

- No AstrBot plugin and no LLM tool registration.
- No write operations in Phase 1.
- API key is never rendered; only its configured/not-configured state is shown.
- The dashboard can be run from the release tree with `-ProjectRoot` so it
  reads production data without copying files into production.

## Verification

```text
30 tests passed
PowerShell scripts parse with UTF-8 BOM
```

## Merge update safety fix

`update_merge.ps1` now stops AstrBot and Broker before hashing data, waits for
file handles to release, hashes only core `.db` files, skips locked files with
a warning, and applies code only after the pre-update fingerprint and backup
are complete. A post-apply mismatch rolls back code and restarts services.
