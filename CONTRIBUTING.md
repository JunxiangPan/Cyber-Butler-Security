# Contributing to Cyber-Butler Security

> Security-sensitive project. Small, reviewable changes are preferred over broad
> refactors. Read `SECURITY.md` and `docs/TROUBLESHOOTING.md` before changing
> ACLs, service identities, the Broker, or the installer.

## 1. Fork safely

1. Fork the repository into your own account.
2. Keep your fork **private** while you work on a security fix. A public fork
   with an unpatched proof-of-concept is a disclosure.
3. Clone with a dedicated account; never commit:

   ```text
   .astrbot_token
   broker_token.txt
   *.dpapi
   totp_secret*
   recovery_hashes*
   update_manifest private keys
   local-overlay.json
   logs containing QQ ids, tokens, or SMTP credentials
   ```

4. Enable 2FA on GitHub and require signed commits if your fork policy allows it.

## 2. Branch and sync upstream security patches

```powershell
git remote add upstream https://github.com/JunxiangPan/Cyber-Butler-Security.git
git fetch upstream
git checkout -b fix/short-description upstream/master
```

For an existing branch:

```powershell
git fetch upstream
git rebase upstream/master
```

Never force-push a branch that another contributor is reviewing. If a security
fix must remain private, coordinate through the process in `SECURITY.md`; do not
open a public pull request before the maintainer confirms disclosure timing.

## 3. Change rules

- **High-tier behavior**: every change to ACLs, task identities, the TOTP vault,
  the Broker policy, or the update trust path needs a regression test.
- **Broker**: server-side policy is authoritative. Never let a model choose
  `risk`, `approval_only`, or a path allowlist.
- **Installer**: use absolute paths and verify the marker/hash after writing it.
  Do not assume the caller's CWD.
- **No new console windows**: Python child processes use `pythonw.exe` where
  appropriate; `subprocess` calls use `creationflags=CREATE_NO_WINDOW`;
  scheduled tasks use the hidden launcher.
- **No silent execution**: `/api/request_approval` remains approval-only;
  actual execution goes through `/request` and explicit verification.
- **Eight languages**: update all eight READMEs for test coverage and security
  statements. Detailed troubleshooting may be bilingual, but the eight-language
  index and links must remain valid.
- **No secrets in tests**: use temporary directories and synthetic tokens.

## 4. Verification before a pull request

```powershell
python -m pytest tests webui/tests -q
powershell -NoProfile -ExecutionPolicy Bypass -Command {
  Import-Module Pester -MinimumVersion 3.4
  Invoke-Pester -Script .\installer\tests
}
python -m py_compile tools/broker.py webui/app.py webui/otp_mailer.py
```

For packaging changes, also build and inspect the archive:

```powershell
python tools/package_release.py
python tools/verify_release.py `
  --manifest update-manifest.json `
  --signature update-manifest.sig `
  --pubkey tools/update_pubkey.pem
```

A release is not publishable unless the final signature is `VALID` and the
manifest hashes match the zip bytes.

## 5. Pull request checklist

```text
[ ] explains the failure mode and the smallest fix
[ ] includes reproduction steps and expected/actual behavior
[ ] updates tests or explains why no test is possible
[ ] does not weaken a deny ACE or hide an error
[ ] does not add a token, password, QQ id, or private path
[ ] keeps `/api/request_approval` approval-only
[ ] keeps the package free of temp files and test logs
[ ] updates the eight-language test-coverage statement if scope changes
```

Use conventional commits, for example:

```text
fix(installer): stop console flash from nvidia-smi polling
feat(broker): bind scoped token to canonical directory
docs(troubleshooting): record UsrClass.dat profile lock
```

## 6. Security reports

Do not open a public issue for a suspected vulnerability. Follow
[`SECURITY.md`](SECURITY.md) § Reporting a Vulnerability. Include the exact
`VERSION`, tier, Windows build, reproduction command, and the smallest log
excerpt. Never include live TOTP codes, scoped tokens, or SMTP credentials.

## Documentation lifecycle (mandatory)

Any pull request that changes an API, installation flow, service identity, ACL, SCM/service behavior, network policy, or other architecture behavior **must update the related documentation in the same pull request**. A pull request without the required documentation update is not merged.

### Documentation rules

- Canonical technical docs live under `docs/`; the eight language README files are entry points, not independent sources of truth.
- `docs/_data/status-v1.6.2.json` is the single source for completed/not-completed features and port ownership.
- Add or update a `## Contents` TOC in long docs.
- Use the archive policy: move obsolete documents to `docs/40-history/archive/` and add `[ARCHIVED - 已废弃]` at the top. Never delete historical docs.
- Run `python -m pytest -q tests/test_docs_consistency.py` before opening a PR.
- Documentation fixes are welcome; use the Documentation issue form.
