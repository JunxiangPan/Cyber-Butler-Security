# Upgrading CBP

CBP is infrastructure. A version bump must never be a forced migration for
existing CI.

## Semantic version promise

### Minor releases: `0.1.x -> 0.1.y`

Minor releases are additive and safe:

- no breaking configuration changes;
- new gates, rules, inputs, and fields are opt-in or have safe defaults;
- old `cbp.json` files are read as-is or migrated in memory;
- legacy fields emit a warning, not an error;
- an old workflow only changes `@v0.1.x` to `@v0.1.y`.

### Major releases: `1.x -> 2.0`

A major version is only for a genuinely incompatible architecture change.
It must include:

- a written migration guide;
- a configuration converter when the mapping is mechanical;
- a maintained previous major line for users who cannot move immediately;
- a deliberate opt-in point, never an automatic forced upgrade.

## v0.1.6 compatibility matrix

| Version | Configuration | Action input | CLI | Result |
|---|---|---|---|---|
| v0.1.0 | `installer_core`, `broker_files` | `installer-core` | `--installer-core` | auto-mapped / alias accepted |
| v0.1.1 | `install-command`, `target_files` | `install-command` | `--install-command` | accepted |
| v0.1.6 | adds `schema_version`, `custom_rules`, `evidence_readers`, `release_body`, `coverage_signature` | all optional | all optional | accepted |

Old configurations without `schema_version` are assumed to be `0.1.0` and
migrated in memory. The actual file is not rewritten unless the user chooses to
commit the update.

Legacy aliases are kept through at least v0.2.x:

```text
installer_core -> install_command
broker_files   -> target_files
measured_files -> target_files
installer-core (Action input and CLI) -> install-command
```

## Deprecation window

A deprecated configuration item must remain usable for at least two minor
releases:

```text
v0.1.x: documentation + DeprecationWarning, behavior unchanged
v0.2.x: behavior unchanged, mandatory warning
v0.3.x or later: removal allowed only after a migration guide exists
```

A deprecated item is never the only way to express a required behavior.

## How to upgrade safely

```bash
# 1. keep the old workflow as a branch/tag
git switch -c upgrade-cbp-0.1.6

# 2. change only the action version
#    uses: owner/cbp-action@v0.1.1
# -> uses: owner/cbp-action@v0.1.6

# 3. run the old config unchanged
python -m cbp.cli --root . --mode enforce

# 4. optionally add schema_version and new opt-in rules
```

If CBP prints `CBP_CONFIG_WARN`, the old configuration still ran. Commit the
suggested field names only after reviewing the output.

## Rollback

Revert the action version to the previous minor. CBP does not rewrite the
checked-in configuration during migration, so rollback is a version change, not
a data recovery operation.

## Upgrade gate

Projects can configure an upgrade script, old configuration fixtures, and a
previous/current JSON Schema comparison. The gate runs in CI and fails closed:

```json
{
  "upgrade_script": "pytest tests/test_upgrade.py",
  "upgrade_fixtures": ["tests/fixtures/v0.1.0_config.json"],
  "previous_schema": "schemas/config.v0.1.1.schema.json",
  "current_schema": "schemas/config.schema.json",
  "allow_breaking_changes": false
}
```

A schema regression requires explicit `allow_breaking_changes: true`.
