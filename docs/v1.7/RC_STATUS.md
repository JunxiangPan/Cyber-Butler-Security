# v1.7.1 Contract RC Status

Status: **RELEASE CANDIDATE — NOT FROZEN**

Branch: `contract/v1.7.1`

Contract file: `docs/v1.7/CONTRACT.md`

Contract SHA256 (candidate):

```text
19b37fd4f2def25a6945bd59affae3128fe466cc0bfd1809d522ba8291b3c12b
```

This hash is a review artifact. It is not a frozen contract, not a tag, and not
a release. Do not let CBE/CBP/CBM/CBC pin to it until the human freeze step.

## Included in this RC

- F2 blocking set (three structural checks + `gate: "blocking"` rules).
- §5.1 report identity (`package_id` = subject, `producer_id` = producer).
- §5.2 bare 64-character lowercase hashes; `sha256:` prefixes are input errors.
- `body_hash_scope: "base"`.
- `artifact_repository` coordinates.
- CBM/CBC body fragments with `NOT_UPLOADED` + `EVIDENCE_ABSENT`.
- `docs/v1.7/CHANGELOG.md` and updated `PINS.md`.
- Schema updates for CBE report and CBP quality manifest.
- 84 v1.7 tests passing.

## Not done

- No contract freeze.
- No new tag.
- No CBE/CBP/CBM/CBC repository edit.
- No v1.7.0 product implementation.
