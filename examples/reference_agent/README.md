# Minimal reference agent

This is intentionally small: it does not delete directly. It submits one
`delete` intent to the local CBS Broker, waits for the human approval, and only
then gives the Broker the TOTP code to execute the approved action.

## Prerequisites

- CBS Broker running on `http://127.0.0.1:18090`
- `tools/broker_token.txt` readable by the agent's restricted account
- A disposable file, not a repository or system path

## Run

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
