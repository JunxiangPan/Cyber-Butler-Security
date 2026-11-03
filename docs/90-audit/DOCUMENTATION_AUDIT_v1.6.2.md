# DOCUMENTATION_AUDIT_v1.6.2

## Contents

- [Five-round plan and result](#five-round-plan-and-result)
- [Canonical directory tree](#canonical-directory-tree)
- [Round 3: eight-language consistency](#round-3-eight-language-consistency)
- [Round 4: checks](#round-4-checks)
- [Honest limitations recorded](#honest-limitations-recorded)
- [Final statement](#final-statement)
- [Package](#package)
- [Round 6: GitHub-facing cleanup](#round-6-github-facing-cleanup)

## Five-round plan and result

| Round | Work | Result |
|---|---|---|
| 1 | Inventory existing docs; design canonical tree | completed |
| 2 | Move current facts into canonical docs; archive legacy READMEs | completed |
| 3 | Compare the eight language READMEs against the shared status facts | completed |
| 4 | Check Markdown fences, active links, terminology, and S4U claims | completed for active docs |
| 5 | Produce this audit and final directory tree | completed |

## Canonical directory tree

```text
README.md
README_en.md / README_zh.md / README_de.md / README_es.md
README_fr.md / README_ja.md / README_ko.md / README_ru.md
SECURITY.md
docs/
├── README.md
├── _data/status-v1.6.2.json
├── 00-overview/
│   ├── project-overview.md
│   ├── quickstart.md
│   ├── architecture-scm.md
│   └── glossary.md
├── 10-security/
│   ├── defense-layers.md
│   ├── scm-service-hardening.md
│   ├── wfp-network-policy.md
│   └── known-limitations.md
├── 20-operations/
│   ├── ports-and-adapters.md
│   └── troubleshooting.md
├── 40-history/
│   ├── incidents/
│   │   ├── s4u-retirement.md
│   │   ├── sqlite-readonly.md
│   │   ├── wfp-empty-rules.md
│   │   ├── acl-self-lock.md
│   │   └── task-rollback.md
│   ├── legacy-readmes/        # archived originals
│   └── releases/              # historical release notes
└── 90-audit/
    ├── DOCUMENTATION_AUDIT_v1.6.2.md
    ├── S4U_AUDIT_v1.6.2.md
    └── QA_FOLLOWUPS_v1.6.2.md
```

## Round 3: eight-language consistency

All eight localized README files contain:

- `CyberButlerAstrBot` and the SCM service statement
- `S4U` explicitly marked as retired
- `6199` explicitly marked as a dynamic OneBot adapter port, not a service
- the same status facts: 6185/18090/8765/8766/5099 verified; WFP audit-only; Light not accepted
- a link to `docs/_data/status-v1.6.2.json`
- a link to `docs/10-security/known-limitations.md`

Files checked:

```text
README_en.md
README_zh.md
README_de.md
README_es.md
README_fr.md
README_ja.md
README_ko.md
README_ru.md
```

## Round 4: checks

- Active canonical docs and eight READMEs: code fences balanced.
- Active canonical links: checked; the active tree has no broken links.
- Archived `40-history/archive/legacy-readmes/` and historical `40-history/releases/` retain old relative links by design; they are archive material, not current guidance.
- Historical S4U mentions remain only as retired/historical explanations. There is no instruction to configure or register S4U.
- Terminology normalized: SCM service, WFP audit-only, dynamic 6199, Session 0, Job Object, known limitations.

## Honest limitations recorded

- WFP enforce mode is not enabled; current mode is audit, `applied=0`.
- Native WFP filter API is not implemented.
- Light tier has no real-machine acceptance.
- v1.6.2 has no clean-VM full install/uninstall acceptance.
- Credential Proxy and full audit-chain replacement remain partial.
- 6199 is not a system service and is absent until the AstrBot OneBot adapter is configured.

## Final statement

The active documentation is structured, deduplicated, and consistent across the eight language entry points. Historical contradictions are archived rather than presented as current guidance.

## Package

The documentation audit is complete; the v1.6.2 package is rebuilt and signed after this audit.

## Round 6: GitHub-facing cleanup

- Replaced the root README with a language selector and kept eight localized entry points; no duplicate `README.md`/`README_en.md` body remains.
- Updated `README-INSTALL.md` from v1.6.1 headings to v1.6.2 and replaced the moved v1.6.1 status link with `docs/_data/status-v1.6.2.json`.
- Added `docs/releases/RELEASE_NOTES_v1.6.2.md` as the copy-paste GitHub Release body.
- Archived the earlier v1.6.2 preview/beta/rc notes with a `Historical / superseded` banner.
- Added `docs/90-audit/GITHUB_WEB_UPDATE_CHECKLIST_v1.6.2.md` for manual GitHub web actions.
- Verified active links after the cleanup; historical archived files are excluded from the active link gate.
- No “Coming soon” placeholder remains in active docs; S4U appears only as retired/historical context.
- Compatibility statement: v1.6.1 remains the previous stable release; v1.6.2 preview/beta/rc are superseded by the final v1.6.2 SCM release note.

## Round 7: UX and anti-footgun pass

- Added a traffic-light status matrix to the root README, every language README, and `docs/00-overview/quickstart.md`.
- Replaced the technical glossary with one-line plain-language cards for SCM, Job Object, WFP, ACL, TOTP, Broker, and OneBot.
- Put the three highest-frequency failure checks at the top of `docs/20-operations/troubleshooting.md`, with copy-paste commands.
- Generated `## Contents` anchors for active long documents.
- Added `docs/00-overview/why-not-faq.md` covering Docker, app-layer blocking, phone TOTP, SYSTEM, WFP audit-only, and 6199.
- Linked the FAQ from the root and eight language READMEs.

Checks: active links 0 broken; active code fences balanced; 8/8 language README checks passed.

## Round 8: documentation lifecycle governance

- CONTRIBUTING.md now requires documentation updates in the same PR for API, install, service, ACL, network, or architecture changes; PRs without docs are not merged.
- `tests/test_docs_consistency.py` checks the status JSON, eight language READMEs, WFP audit-only truth, 6199 ownership, active links/fences, and archive markers.
- `.github/workflows/security-tests.yml` runs the documentation consistency test on push and pull request.
- ROADMAP.md now requires a seven-round documentation audit before every major release.
- Obsolete documents are moved to `docs/40-history/archive/` and marked `[ARCHIVED - 已废弃]`.
- Added `.github/ISSUE_TEMPLATE/documentation.yml` for broken links, typos, misleading text, missing steps, and translation inconsistencies.
