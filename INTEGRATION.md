# Integration contract

CBS is a **local approval gateway**, not a kernel sandbox. It can only protect
operations that actually pass through its Broker API.

## Non-negotiable requirements for an external agent

- The agent must route every destructive file operation through the CBS Broker:
  `http://127.0.0.1:18090/`.
- The agent must not call `os.remove`, `shutil.rmtree`, PowerShell
  `Remove-Item`, shell `rm`, direct Win32 file APIs, or arbitrary Python
  execution as an alternative path around the Broker.
- The agent must run under a restricted account that cannot write outside its
  approved workspace. If the agent can write directly to `C:\Windows`,
  `C:\CyberButler	ools`, or the TOTP vault, CBS cannot prevent the damage.
- The agent must not read or copy `tools/broker_token.txt`. A local process
  that obtains the Broker token can impersonate the agent.
- Treat the Broker as loopback-only. Do not expose port 18090 to a LAN, a
  container network, or a remote browser.

## What CBS does not do

- It does not intercept arbitrary OS syscalls.
- It does not stop an agent that executes `os.remove()` or a shell command
  directly.
- It does not provide mTLS between local processes. The current transport is
  loopback HTTP plus a bearer token. Process SID/path attestation and mTLS are
  future work.
- It does not stop a local administrator from taking ownership of a staging
  directory or changing ACLs.
- It does not guarantee physical erasure on SSDs, copy-on-write filesystems,
  backups, snapshots, or storage-controller caches.
- WFP controls network egress only; it cannot block a local file deletion.

## Physical separation

The TOTP authenticator must be on a different physical device from the agent
host. Do not install Google Authenticator, Microsoft Authenticator, or a
compatible OTP app inside an Android subsystem, emulator, or the same Windows
machine. A screen-capturing agent can otherwise read the approval code.

## Trust anchor

Approval only protects requests that reach the Broker. An agent that bypasses
the Broker is outside CBS's enforcement boundary. Deploy CBS together with a
restricted OS account, filesystem ACLs, and network policy; do not treat the
presence of CBS as proof that an arbitrary third-party agent is contained.
