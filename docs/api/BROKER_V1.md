# CBS Broker v1 API reference

Status: **P0-2 draft; no compatibility promise until the v1.7.1 contract freezes.**

The Broker is loopback-only at `http://127.0.0.1:18090`. Every request except
`/health` requires:

```text
X-Broker-Token: <contents of tools/broker_token.txt>
```

Do not read the token from an agent-reachable path without an ACL boundary.

## POST /request

Request schema: [`schemas/broker/v1/request.schema.json`](../../schemas/broker/v1/request.schema.json)

```json
{"action": "delete", "target": "C:/temp/demo.txt", "reason": "demo", "approval_only": true}
```

Returns a challenge id and `status: requires_totp` for a normal request.

## GET /api/request_approval/status?id=<challenge-id>

Status schema: [`schemas/broker/v1/approval-status.schema.json`](../../schemas/broker/v1/approval-status.schema.json)

Returns `pending`, `approved`, `denied`, `expired`, or `unknown`. A scoped token
may appear only after approval; the caller cannot choose its scope.

## POST /verify

Verify schema: [`schemas/broker/v1/verify.schema.json`](../../schemas/broker/v1/verify.schema.json)

```json
{"id": "<challenge-id>", "code": "123456"}
```

The code is human-supplied. The Broker owns approval scope and audit; the SDK
never accepts a caller-supplied scope.

## Clients

- Python: [`sdk/python/cbs_client.py`](../../sdk/python/cbs_client.py)
- TypeScript: [`sdk/typescript/client.ts`](../../sdk/typescript/client.ts)
- Reference agent: [`examples/reference_agent/agent.py`](../../examples/reference_agent/agent.py)

## Conformance

`tests/test_sdk_python.py` exercises the three endpoints against a local
Broker-shaped server and checks the token header, approval-only flag, and the
absence of caller-supplied `scoped_minutes`.
