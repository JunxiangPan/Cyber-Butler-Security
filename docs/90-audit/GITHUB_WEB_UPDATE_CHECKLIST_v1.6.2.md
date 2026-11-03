# GitHub web update checklist — v1.6.2

Generated from the local repository state. Items marked “manual” cannot be verified from local files.

## Repository home / README

- [ ] Confirm the GitHub default branch shows the new `README.md` language selector.
- [ ] Verify all eight language links resolve on the rendered GitHub page.
- [ ] Remove old badges or screenshots that imply v1.6.1-only behavior.
- [ ] Confirm the README says AstrBot uses the SCM service `CyberButlerAstrBot`, not S4U.
- [ ] Confirm WFP is described as audit-only.

## Releases page

- [ ] Create/publish the v1.6.2 release using `docs/releases/RELEASE_NOTES_v1.6.2.md`.
- [ ] Mark v1.6.2 as a pre-release unless clean-VM acceptance is complete.
- [ ] Edit or unpublish the old `v1.6.2-preview`, `v1.6.2-beta`, and `v1.6.2-rc` releases so they do not look current.
- [ ] Keep v1.6.1 as the previous stable release; do not mark v1.6.2 stable before acceptance.
- [ ] Upload only the final signed assets; never upload the private key.
- [ ] Verify the release asset hashes match the signed manifest.

## Issues

- [ ] Check open issues that claim S4U is supported; reply with the SCM architecture link and close if resolved.
- [ ] Search for “S4U” and “Task Scheduler” in open issues; label/deprecate stale reports.
- [ ] Close duplicate High-tier service/SQLite readonly reports with a link to `docs/40-history/incidents/sqlite-readonly.md`.
- [ ] Check whether an issue template exists remotely; if yes, update it to ask for `Get-Service CyberButlerAstrBot` and `service-astrbot.log`.

## Discussions

- [ ] Unpin any preview/beta announcement.
- [ ] Pin a v1.6.2 post that links the final release notes and explicitly states WFP audit-only.
- [ ] Update or close discussion threads that recommend S4U or a SYSTEM launcher.
- [ ] Add a note that 6199 is a dynamic OneBot adapter port, not a service.

## GitHub Actions

- [ ] Confirm `.github/workflows/security-tests.yml` runs against the new docs/SCM installer branch.
- [ ] Remove or update any workflow step that expects an S4U task.
- [ ] Confirm no workflow publishes unsigned packages.

## Profile / social preview

- [ ] Update repository description if it still says “preview” or “v1.6.1”.
- [ ] Check pinned repositories and project boards for stale v1.6.2 preview links.
