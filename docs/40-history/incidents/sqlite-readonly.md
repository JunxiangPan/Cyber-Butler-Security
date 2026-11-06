# Incident: SQLite readonly under High isolation

## Contents

- [Symptom](#symptom)
- [Root causes found](#root-causes-found)
- [Alternatives predicted and abandoned](#alternatives-predicted-and-abandoned)
- [Resolution](#resolution)

## Symptom

`sqlite3.OperationalError: attempt to write a readonly database` or `unable to open database file` while external agent started under the service account.

## Root causes found

- High's data ACL initially made the data root read-only; SQLite needs to create `-wal` and `-shm` beside the database.
- A stale broad `Everyone: DeleteSubdirectoriesAndFiles` deny on the install root was inherited by data.
- The service's first binary did not write a probe before launching Python, so the failure looked silent in Task Scheduler.

## Alternatives predicted and abandoned

- Move the DB into a writable subdirectory: rejected because external agent's database path is fixed at `data\data_v4.db`.
- Run external agent as SYSTEM: rejected, loses High isolation.
- Use Medium: works but not High.
- Replace the DB file with a copy: rejected as unsafe without a consistent SQLite backup; the final design keeps the existing data and grants the service account write/delete on the data root.

## Resolution

Data write probe in the service wrapper; SQLite write test; data ACL repair; SCM service starts external agent and 6185 listens.
