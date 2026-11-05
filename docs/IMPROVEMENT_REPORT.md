# IMPROVEMENT_REPORT

Date: 2026-11-05 (Asia/Singapore)

## 1. Task status

| Task | Status | Evidence |
|---|---|---|
| A-1 mutation check | DONE | `quality/artifacts/mutation/targets.json`, `result.txt`; `MUTATION_OK` |
| A-2 PROOF self-seal | PARTIAL | `tools/Run-Final-Acceptance.ps1` prints `PROOF_SHA256` and writes `## PROOF SEAL`; `sign_release.py` compares it. No VM proof exists yet. |
| A-3 nonce hard validation | PARTIAL | length >=16, two character classes, 30-entry history implemented in `Run-Final-Acceptance.ps1`; not executed on VM. |
| A-4 test PowerShell syntax | DONE | `quality/parse_ps_tests.ps1`: `PS_TESTS_PARSED=46`, `PS_TESTS_ERRORS=0`; artifact `quality/artifacts/ps_tests_parse.txt` |
| A-5 coverage declaration | DONE | BUILD_REPORT has `## Static Analysis Coverage` |
| A-6 two mandatory report sections | DONE | BUILD_REPORT contains both sections; `sign_release.py` rejects missing/short sections |
| A-7 regression log | PARTIAL | `docs/regression-log.md`; BUG-002/003/004 have test IDs; BUG-001 is OPEN because no real timing test exists |
| A-8 doc keyword coverage | NEEDS-DECISION | second round |
| A-9 CI dual mode | NEEDS-DECISION | second round |

## 2. A-1 mutation details

The real assertion text was inverted in place, the target test was run, and the
original file was restored in a `finally` block. No `if False` wrapper was used.

| Target | Original | Mutated | Result |
|---|---|---|---|
| `tests/test_acl_model.py:69` `test_owner_can_read_vault` | `assert read_vault(...).startswith("vault-")` | `assert not read_vault(...).startswith("vault-")` | KILLED (exit 1), restored |
| `tests/test_approval_preview.py:45` `test_delete_preview_never_reads_file_content` | `assert "do-not-print-this" not in text` | `assert not "do-not-print-this" not in text` | KILLED (exit 1), restored |
| `tests/test_approval_preview.py:77` `test_external_read_warning_is_objective_not_a_verdict` | `assert "最近读取了外部网页/文件" in text` | `assert not "最近读取了外部网页/文件" in text` | KILLED (exit 1), restored |

Restored SHA-256 values are recorded in `result.txt`. The source files are
byte-identical to the pre-mutation state.

## 3. A-4 evidence

```text
PS_TESTS_PARSED=46
PS_TESTS_ERRORS=0
```

Artifact: `quality/artifacts/ps_tests_parse.txt`.

## 4. A-5 coverage

- mypy: 53/53 Python source files under `tools`, `webui`, `installer`; excludes
  `tests`, `webui/.venv` and caches.
- pyright: 53/53 Python source files under the same roots.
- PSSA: 88/89 runtime PowerShell files under `installer`, `tools`, `webui`;
  `tests` and generated artifacts are excluded and only syntax-parsed.
- vulture: 53/53 production Python files, with the documented 67-entry dynamic
  entry whitelist.

These counts are stated in BUILD_REPORT rather than hidden.

## 5. A-7 regression list

| BUG | Test | Manifest | Status |
|---|---|---|---|
| BUG-001 token ACL timing | installer main ACL lifecycle test (not a timing test) | no dedicated timing file | OPEN |
| BUG-002 redaction backspace | `tests/test_regression_hygiene.py::test_dashboard_error_redaction_uses_real_word_boundaries` | file in MANIFEST | CLOSED (source regression) |
| BUG-003 dangerous scanner backspace | `tests/test_regression_hygiene.py::test_dashboard_dangerous_command_patterns_use_word_boundaries` | file in MANIFEST | CLOSED (source regression) |
| BUG-004 newline path acceptance | `tests/test_regression_hygiene.py::test_path_guard_rejects_newline_control_character` | file in MANIFEST | CLOSED (source regression) |

`checks/MANIFEST.sha256` covers the test file; `docs/regression-log.md` records
the limitation that BUG-001 still has no timing test.

## 6. B evaluations

### B-1 real ACL fixture

**NEEDS-DECISION.** The current host is a normal workstation and the installer
does not create test accounts. A local temporary account is technically
possible only with an elevated administrator token; it also creates a real
local account, profile and ACL state. A safe proposal is an isolated test
account with a forced logout/reset, but that is a system-level change and needs
human approval. No account was created.

### B-2 1000 concurrency / broker kill / disk full

**NEEDS-DECISION.** Rough estimates:

- 1000 concurrent requests: 3-10 minutes plus handle sampling; not suitable for
  every CI run.
- Broker kill during a request: under 1 minute, but needs a deterministic
  fail-closed assertion.
- 600 MB capacity: 1-3 minutes and writes ~600 MB; not suitable for default CI.
- Recommendation: `-Mode Deep`, manual or nightly, not every release gate.

### B-3 vulture audit CSV

**NEEDS-DECISION.** A 67-row CSV with a reason and caller for every symbol was
not produced in this round. The current whitelist is a gate input, not proof
that each symbol is dead or safe to delete.

### B-4 assertions.json seal

**NEEDS-DECISION.** Proposed: add `checks/assertions.json` to MANIFEST; updates
must go through `update_assertions.ps1` requiring an operator passphrase and
writing a diff + reason. Not implemented.

### B-5 key management

**DONE (draft only).** `docs/KEY_MANAGEMENT.md` covers offline/DPAPI storage,
two-person confirmation, append-only signing log requirements and leak
revocation. No key material was moved or exported.

### B-6 revocation

**DONE (template only).** `templates/REVOKED_TEMPLATE.md`; `verify_release.py`
does not yet read a revoked list, so this remains a proposal.

### B-7 security attributes

**DONE (draft only).** `docs/SECURITY_ATTRIBUTES.md` lists the six requested
attributes with evidence and gaps. It is a human review checklist, not a PASS.

## 7. Candidate

- `public-release-v1.6.3.zip`
- SHA-256: `19b45d9f4330db185b133b06a90e3643d58175d3755c14adb96fcaf099ca1f4c`
- `BUILD_REPORT.md` SHA-256:
  `a35110ca63e528c8e0c3817fb037c7f156f16ef84f6183931268862ec5e625d5`
- Challenge: `A-ROUND1-20261105-0010`
- Not signed, not uploaded, not marked Latest.

## 8. Honest conclusion

A-1, A-4, A-5 and A-6 are implemented and have local evidence. A-2 and A-3 are
implemented but cannot be called complete until a real VM proof is generated.
A-7 is partial: BUG-001 has no real timing test. A-8/A-9 and B-1 through B-4
were not implemented in this round; B-5/B-6/B-7 exist only as drafts. Signing
remains prohibited.
