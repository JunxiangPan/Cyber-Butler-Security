# Regression Log

Every entry must have a reproducible test ID. A BUG is CLOSED only when the
test exists and the test file is present in `checks/MANIFEST.sha256`.

| BUG | Date | Symptom | Root cause | Test ID | In MANIFEST | Status |
|---|---|---|---|---|---|---|
| BUG-001 | 2026-11-03 | `broker_token.txt` ACL grant ran before the token existed | installer one-shot ordering race | `installer/tests/Installer.Main.Tests.ps1` (ACL lifecycle) | NO (no timing test) | OPEN |
| BUG-002 | 2026-11-04 | `Authorization`/`Bearer` redaction silently stopped matching | backspace control byte replaced `\b` | `tests/test_regression_hygiene.py::test_dashboard_error_redaction_uses_real_word_boundaries` | YES (MANIFEST entry covers file) | CLOSED (source regression) |
| BUG-003 | 2026-11-04 | dangerous command scanner accepted `rm`/`del`/`iex` | backspace control byte replaced `\b` | `tests/test_regression_hygiene.py::test_dashboard_dangerous_command_patterns_use_word_boundaries` | YES (MANIFEST entry covers file) | CLOSED (source regression) |
| BUG-004 | 2026-11-04 | newline/control path was accepted by `win_path_guard` | validation only rejected NUL and `..` | `tests/test_regression_hygiene.py::test_path_guard_rejects_newline_control_character` | YES (MANIFEST entry covers file) | CLOSED (source regression) |

## Notes

- BUG-001 remains OPEN because the existing installer tests assert the ACL
  helper, not the **timing** of token creation followed by grant. A real timing
  test needs a fake delayed token provider and is intentionally not marked
  closed here.
- The three BUG-002/003/004 tests are exact-source regression checks, not live
  PowerShell execution. They catch the historical corruption but do not prove
  dashboard behavior end to end.
- No BUG is CLOSED until its manifest entry is verified and the corresponding
  test passes in the release pipeline.
