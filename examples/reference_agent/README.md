# Minimal reference agent

This is intentionally small: it does not delete directly. It submits one
`delete` intent to the local CBS Broker, waits for the human approval, and only
then gives the Broker the TOTP code to execute the approved action.

## Prerequisites

- CBS Broker running on `http://127.0.0.1:18090`
- `tools/broker_token.txt` readable by the agent's restricted account
- A disposable file, not a repository or system path

## One-command demo

From the repo root, with the Broker and WebUI running:

```powershell
pwsh -File examples/reference_agent/demo.ps1
```

It creates one disposable temp file, submits one delete request, waits for the
human decision, and forwards a supplied TOTP only if `CBS_TOTP` is set. It
never reads the TOTP secret.

## Run directly

```bash
python examples/reference_agent/agent.py C:\temp\cbs-demo.txt
```

Approve in the WebUI. If verification is required, set the one-time code:

```bash
set CBS_TOTP=123456
python examples/reference_agent/agent.py C:\temp\cbs-demo.txt
```

The reference agent never reads the TOTP secret. It only forwards the
human-supplied code to the Broker; the Broker owns the execution and audit.
