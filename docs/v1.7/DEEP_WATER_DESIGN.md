# v1.7.0 deep-water design / interface list

Status: design only where stated. A design is not an implementation.

## 1. Temporal Replay

Goal: a read-only timeline for audit events, with before/after content hashes
and actor/request identifiers. Replay never re-executes a file action.

Interface (`tools/temporal_replay.py`):

```python
@dataclass(frozen=True)
class ReplayEvent:
    event_id: str
    at: str                 # ISO-8601 UTC
    actor: str
    request_id: str
    action: str
    target: str
    before_sha256: str      # bare 64 lowercase hex, or "" for create
    after_sha256: str       # bare 64 lowercase hex, or "" for delete
    scope: str

def build_timeline(events: Iterable[dict]) -> list[ReplayEvent]
def replay_summary(events: Iterable[dict]) -> dict
```

Rules:
- sort by `at`, then `event_id`; duplicate `event_id` is an input error;
- hashes must be bare 64-character lowercase hex, never `sha256:` prefixed;
- a changed target must have both before and after hashes;
- unknown fields are rejected in strict mode;
- no filesystem write and no action execution.

Evidence: positive timeline plus duplicate/hash/timestamp negative tests.

## 2. Diff Boundary

Goal: define what a bounded write is allowed to change, before execution.

Interface (`tools/diff_boundary.py`):

```python
@dataclass(frozen=True)
class DiffBoundary:
    root: str
    max_files: int = 1
    max_bytes: int = 262144
    allow_create: bool = False
    allow_delete: bool = False

def check_diff(boundary: DiffBoundary, changes: Iterable[dict]) -> tuple[bool, str]
```

Rules:
- every changed path must resolve under `root` (no traversal/symlink escape);
- path count, total byte count and create/delete flags are enforced;
- binary or text content is outside this semantic layer; only path/size/kind;
- a negative sample is a rejection, never a pass.

## 3. IPC / Named Pipe + Helper

Goal: Windows named pipe between Broker and a user-session Helper, with
explicit ACL, bounded message size, connect timeout and disconnect cleanup.

Proposed interface:

```text
\\.\pipe\CyberButler.Helper.v1
  request:  {version, request_id, action, payload_sha256}
  response: {version, request_id, ok, result_sha256}
```

Requirements:
- pipe ACL restricted to SYSTEM + the service account + the interactive user;
- `PIPE_REJECT_REMOTE_CLIENTS`; 5s connect timeout; 1 MiB max message;
- helper is a separate process with a Job Object and a heartbeat;
- disconnect closes the handle and records an audit event;
- no long-lived privileged helper in v1.7.0.

Status: design only. This item is blocked until a Windows test host is available
for ACL/disconnect/timeout tests.

## 4. Optional MXC

MXC is optional and must not block v1.7.0. Export policy and schema round-trip
only; never silently apply a policy. No implementation is committed by this
design.

## Implementation status

- Temporal Replay: read-only audit timeline implemented; tests/evidence; no audit rewrite.
- Diff Boundary: `tools/diff_boundary.py` is called before write_file/overwrite in
  `tools/broker.py`; fail-closed; negative tests.
- IPC: frame codec + `tools/ipc_pipe.py` transport code. BLOCKED because the client
  connect timed out in this non-interactive session, the official Evaluation ISO
  download is BLOCKED, and there is no multi-account Windows ACL test VM. It is
  not PASS.
- MXC: optional/deferred; not part of the v1.7.0 blocking scope.
