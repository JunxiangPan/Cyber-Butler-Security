# Test Matrix / 测试矩阵

## Contents

- [1. Acceptance tiers](#1-acceptance-tiers)
- [2. CI matrix](#2-ci-matrix)
- [3. Claim-to-test map](#3-claim-to-test-map)
- [4. Required release gates](#4-required-release-gates)
- [5. AppContainer boundary](#5-appcontainer-boundary)
- [6. CI guard for this matrix](#6-ci-guard-for-this-matrix)

> This page maps every public security claim to evidence. A missing test is a
> known gap, not an implied pass. CI cannot replace a real Windows acceptance
> run.

## 1. Acceptance tiers

| Tier | Automated tests | Real-machine E2E | Release status |
|---|---|---|---|
| **High** | pytest + Pester + installer checks | ✅ completed 2026-11-02<br>install, service startup, TOTP, SCOPED, uninstall | **accepted** |
| **Medium** | pytest + Pester + partial installer checks | ⚠️ multiple partial runs; no complete E2E acceptance | partial |
| **Light** | pytest + Pester contracts | ❌ **required and not yet run** | **not accepted** |

**Light real-machine testing is mandatory from v1.6.3 onward.** Light is a
security tier, not a disposable test mode; it must cover install, service
startup, read/write policy, TOTP/vault behavior where supported, and uninstall.

## 2. CI matrix

Current `.github/workflows/security-tests.yml`:

| Job | OS | What it proves | What it cannot prove |
|---|---|---|---|
| pytest | ubuntu-latest | pure policy/unit/contract tests; privacy scan | Windows ACL/WFP/Job behavior |
| pytest | windows-latest | Python tests and privacy scan on Windows | interactive installer, real machine accounts, WFP admin behavior |

The workflow runs `privacy_scan.py` and `pytest -q` on both OSes. It does **not**
run the WPF installer, create real service accounts, exercise WFP filters, or
perform a real-machine Light acceptance. Those are manual release gates.

## 3. Claim-to-test map

| Security claim | Evidence | Status |
|---|---|---|
| ACL separation for High | `tests/test_acl_effective.py`; `installer/tests/Installer.Acl.Tests.ps1`; High E2E | High verified; Light not |
| TOTP replay/brute-force limits | `tests/test_totp_replay.py`, `test_totp_bruteforce.py`, `test_broker_wrong_totp.py` | automated |
| approval-only never executes | `tests/test_broker_policy.py`, `test_send_policy_contract.py` | automated |
| SCOPED 30 is directory/time bound | `tests/test_broker_policy.py` | automated |
| TOCTOU handle binding | `tests/test_toctou.py`, `test_toctou_broker.py`, `test_path_guard.py` | automated + High E2E |
| quarantine on delete | `tests/test_toctou.py` (quarantine path) | automated; real restore gate pending |
| 8.3 / symlink / traversal rejection | `tests/test_path_guard.py` | automated (Windows symlink case may skip) |
| Job Object resource limits | `tests/test_job_limits.py` | constants/policy only; Windows kill-limit integration pending |
| WFP policy and block plan | `tests/test_wfp_policy.py`, `test_wfp_guard.py` | policy/plan only; **native filter not integrated** |
| Tripwire log rotation | `tests/test_wfp_tripwire.py` | parser/cursor only; real firewall log not yet wired |
| audit hash chain | `tests/test_audit_chain.py` | module; Broker mirror exists but full event coverage is partial |
| watchdog fail-closed | `tests/test_watchdog.py`; plugin health check | automated + handler check |
| SBOM hash check | `tests/test_sbom.py`; installer pip hook | webui requirements covered; not all dependency trees |
| denial jitter / request rate limit | `tests/test_rate_limit.py` | automated |
| preview/redaction | `tests/test_approval_preview.py` | automated |
| port hijack check | `tests/test_port_guard.py` | decision logic; Windows admin integration pending |
| physical separation | `tests/test_physical_separation.py`; WebUI banner | state/banner; installer enforcement pending |
| uninstall anti-rebound | Pester installer tests; High E2E | partial; WFP guard removal after reinstall still pending |
| AppContainer sandbox | **none** | **not implemented; do not claim** |
| MXC policy export | **none** | backlog, not implemented |

## 4. Required release gates

```text
[ ] High: automated + real-machine E2E + signed package
[ ] Medium: automated + at least one complete real-machine E2E
[ ] Light: automated + complete real-machine E2E
[ ] native WFP filter path tested on Windows with admin
[ ] WFP tripwire fed by the actual configured log
[ ] Job Object memory/CPU/kill behavior observed on Windows
[ ] audit chain verifies after rotation and restart
[ ] uninstall anti-rebound observed with agent running
[ ] threat model reviewed before v2.0 SDK work
```

## 5. AppContainer boundary

AppContainer is **not implemented** in v1.6.x. Current controls are separate
account + ACL + WFP-backed egress + Job Object + Broker approval. They do not
provide a restricted-token/AppContainer sandbox or syscall mediation. See
[THREAT_MODEL.md](../THREAT_MODEL.md) and
[SECURITY.md](../SECURITY.md) for residual risks.

## 6. CI guard for this matrix

`tests/test_test_matrix.py` checks that this page still contains the Light
real-machine row and the AppContainer non-claim. It does not turn documentation
into a security test; it only prevents accidentally deleting the disclosure.
