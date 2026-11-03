# GitHub release checklist — v1.6.2

## Before publishing

- [ ] Use the final four assets from `release-assets-v1.6.2` (not any local test build).
- [ ] Confirm the ZIP is named exactly `public-release-v1.6.2.zip`.
- [ ] Confirm `VERSION` inside the ZIP is `1.6.2`.
- [ ] Confirm `python tools/verify_release.py ...` prints `VALID`.
- [ ] Complete the clean-VM check with `tools/clean-vm-acceptance.ps1` and keep the JSON evidence.
- [ ] Decide the release channel. If clean-VM acceptance is not complete, publish as a **pre-release**, not Latest.

## Tag and title

- **Tag:** `v1.6.2`
- **Target:** the commit containing the `VERSION` file with `1.6.2`
- **Release title:** `Cyber-Butler Security v1.6.2`
- **Release notes:** copy `docs/releases/GITHUB_RELEASE_v1.6.2.md`

## Upload exactly four assets

```text
public-release-v1.6.2.zip
update-manifest.json
update-manifest.sig
update_pubkey.pem
```

Do not upload:

```text
private keys
local repair scripts
test-only ZIPs
final/rc/preview builds
```

## Existing preview releases

- [ ] Unpublish or mark as pre-release every old `v1.6.2-preview`, `v1.6.2-beta`, and `v1.6.2-rc` release.
- [ ] Add a note to any retained historical release pointing to the current v1.6.2 release.
- [ ] Do not delete historical tags or release notes; keep them for auditability.
- [ ] Ensure only the final v1.6.2 release is marked **Latest** after clean-VM acceptance.

## Repository surface

- [ ] Default branch README shows v1.6.2 and the SCM architecture.
- [ ] All eight language README links resolve.
- [ ] `CONTRIBUTORS.md` is reachable from the README and release notes.
- [ ] Issue template includes the Documentation / 文档纠错 form.
- [ ] Pinned discussions no longer recommend S4U or a SYSTEM launcher.

## Post-publication

- [ ] Verify the four downloaded assets against the published SHA256 values.
- [ ] Run the documented verification command from a clean directory.
- [ ] Record the release URL and acceptance evidence in the project operations log.
