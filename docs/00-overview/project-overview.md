# Project overview

## Contents

- [Scope](#scope)
- [Non-goals](#non-goals)
- [Canonical status](#canonical-status)

Cyber-Butler Security (CBS) is a defensive control plane for self-hosted LLM agents. It provides installer-driven isolation, TOTP approvals, a local broker, network guard scaffolding, and operational diagnostics.

## Scope

- Windows 10/11 x64, PowerShell 5.1, Python 3.10-3.13.
- High tier: dedicated local service account, native SCM service, ACL-separated data, TOTP approval.
- Medium/Light: reduced isolation; not equivalent to High.

## Non-goals

- Not a sandbox for arbitrary untrusted code.
- Not a replacement for OS patching, EDR, backups, or human review.
- Not a guarantee that an agent cannot exfiltrate data through every possible channel.

## Canonical status

The single source of truth is [`docs/_data/status-v1.6.2.json`](../_data/status-v1.6.2.json). The eight language README files mirror that status and must not invent different completion claims.
