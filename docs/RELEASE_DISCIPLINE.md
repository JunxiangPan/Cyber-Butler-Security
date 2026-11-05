# Release discipline

A fix that exists only on a developer machine is not a fix. It is not released,
not auditable, and must not appear in release notes.

## Rules

1. Every change is committed to a real branch and pushed to
   `origin/<branch>` before it can be claimed as fixed.
2. `Run-ReleasePipeline.ps1` refuses a dirty worktree and refuses a HEAD that
   differs from `origin/release/v1.6.3`.
3. Release notes and CHANGELOG entries may describe only commits reachable from
   the pushed branch.
4. Every claimed fix needs a failing-before/passing-after test in CI. If no test
   exists, the item stays in `NOT_FIXED_THIS_ROUND`.
5. Never invent a version, commit, tag, release asset, signature, or VM result.
   Absence of `ACCEPTANCE_PROOF.md`, a valid signature, or a PASS QA report means
   the release remains blocked.
