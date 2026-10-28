# v1.0.0 — Security-Hardened Public Release

**Release date:** 2026-10-29  
**License:** GNU AGPL-3.0  
**Documentation presentation update:** V1.1 (project structure, full release notes, threat-model residual-risk update)

> [!WARNING]
> **Unofficial QQ protocol — use a test account only.**
>
> This project depends on third-party, **non-official** QQ protocol clients such as SnowLuma. Such use may violate Tencent's *QQ Software License and Service Agreement* and can result in account restriction, suspension, or **permanent account bans**. The maintainers provide no guarantee against account loss, data loss, legal disputes, or financial damage.
>
> This project is for **personal study, research, and local security-technical exchange only**. Commercial use, illegal profit-making, black-market activity, and malicious disruption are strictly prohibited. Use an isolated test account and a test machine; never connect a primary QQ account.

## Overview

V1.0.0 is the first public, security-hardened release of the Cyber Steward architecture for a Windows-hosted QQ agent. It focuses on one principle:

> **The LLM may request a dangerous action, but it must not be able to execute it without a human second factor.**

The release includes a dual-account isolation model, an ACL-protected TOTP vault, a SYSTEM Broker for destructive file actions, TOTP-gated file egress, prompt-injection gating, daily auditing, and an API-only fallback for machines without a large GPU or Ollama.

## At a Glance

| Area | Status |
|---|---|
| Public security tests | **11 passed locally** (9 original + 2 new regressions) |
| GitHub Actions | Workflow committed: Ubuntu + Windows, Python 3.12 |
| Core security model | ACL + loopback Broker + TOTP + audit |
| Local model support | Optional (Ollama) |
| API-only mode | Supported (`config.lite.example.json`) |
| Documentation | 8 languages, 9 README files |
| License | AGPL-3.0 |
| QQ transport | **Unofficial; test accounts only** |

## Security Architecture

### 1. Dual-account isolation

- AstrBot runs under a dedicated low-privilege service account (`YOUR_SERVICE_USER`).
- The QQ/SnowLuma desktop session is separate from the AstrBot service account.
- AstrBot has no read/delete/overwrite permission on the TOTP vault.
- The SYSTEM Broker is the only component allowed to execute approved destructive actions.

### 2. ACL boundary

The vault is protected by an **explicit deny ACE** for the service account, not merely by inheritance. The shared folder allows creation and reading, but not deletion or overwrite of existing files. See the full ACL table in [SECURITY.md](SECURITY.md).

### 3. TOTP Broker

- AstrBot calls a loopback-only HTTP Broker (`127.0.0.1:18090`) with a local broker token.
- The Broker sends a one-time TOTP challenge over the configured chat transport.
- A wrong code returns **HTTP 403** without consuming the pending request.
- TOTP and recovery codes are single-use; a 120-second in-memory replay cache rejects repeated TOTP values.
- Every approved action is written to an audit JSONL.

### 4. File-egress control

- Whitelisted directory + non-sensitive name + trusted owner → direct send.
- Sensitive names, other paths, archives, URLs, or batch/size overflow → TOTP.
- File ownership is checked to stop the “copy into the whitelist, then send” bypass.

### 5. Prompt-injection gate

The owner QQ account is trusted. Other senders are stopped before the model when they match injection or privilege-escalation patterns; attempts are logged.

### 6. API-only graceful fallback

`astrbot_plugin_cloud_fallback` checks the local `local_qwen36` configuration and Ollama port `11434`. If the local model is disabled or unreachable, it switches the private session to DeepSeek and logs:

```text
未检测到本地模型，已自动切换为纯云端模式
```

Game-mode and weekly self-heal scripts skip local model unload/reload with `Skipped (Ollama not found)` or `Skipped (Ollama not running)` instead of failing.

## Security Hardening Included

This release also closes four audit findings:

- **TOTP brute force:** five failed attempts clear the pending request, set a 300-second verification lockout, return HTTP 429, and write an audit entry.
- **SYSTEM runtime injection:** `tools/broker.py` runs a startup ACL verifier and refuses to start if `tools/` or `AstrBot/.venv` is writable by a broad principal. See `tools/harden_broker_runtime.ps1` and `tools/verify_broker_acl.ps1`.
- **Case/hard-link bypass:** owner comparison is casefolded on both sides; `st_nlink > 1` forces TOTP.
- **Security Gate fail-open:** unknown `umo` platforms are logged and blocked by default.

## Automated Tests: 11 Passed

The public release contains a reproducible pytest suite:

```text
tests/
├── conftest.py
├── test_acl_model.py
├── test_broker_wrong_totp.py
├── test_totp_bruteforce.py
├── test_totp_replay.py
└── test_security_gate.py
```

Local result:

```text
11 passed in 0.36s
```

Coverage:

- explicit ACL deny wins over an allow ACE;
- service-account vault read raises `PermissionError`;
- wrong TOTP returns **403** and preserves the pending request;
- a valid TOTP cannot be reused;
- a recovery code cannot be reused;
- five bad TOTP attempts lock verification with HTTP 429;
- unknown chat platforms fail closed;
- prompt injection from a non-owner is stopped before the model;
- the owner is exempt;
- benign text is not blocked.

Run it locally:

```bash
python -m pip install -r requirements-dev.txt
python -m pytest -q
```

## CI/CD Pipeline

Workflow: `.github/workflows/security-tests.yml`

- Ubuntu Latest
- Windows Latest
- Python 3.12
- `python -m pytest -q`
- Runs on every push and pull request

**Status transparency:** the workflow is committed and the suite passes locally (11/11). A GitHub Actions run is triggered by the next push; this release note does not claim a green remote badge until that run completes. Check the Actions tab for the authoritative remote result.

## Project Structure

The root now exposes the security core and tests directly:

```text
.
├── README.md                  # English default
├── README_zh.md               # Chinese
├── README_en.md               # English mirror
├── README_ja.md               # Japanese
├── README_ko.md               # Korean
├── README_es.md               # Spanish
├── README_fr.md               # French
├── README_de.md               # German
├── README_ru.md               # Russian
├── SECURITY.md                # threat model, ACL table, TOTP replay, adapter guide
├── LICENSE
├── config.pro.example.json
├── config.lite.example.json
├── requirements-dev.txt
├── .github/workflows/security-tests.yml
├── tests/
├── overlay/astrbot/
├── plugins/
├── tools/broker.py
└── docs/
```

Full breakdown: [README.md](README.md) → **Project Structure**.

## 8 Languages

- 🇨🇳 中文 (简体): `README_zh.md`
- 🇬🇧 English: `README.md` and `README_en.md`
- 🇯🇵 日本語: `README_ja.md`
- 🇰🇷 한국어: `README_ko.md`
- 🇪🇸 Español: `README_es.md`
- 🇫🇷 Français: `README_fr.md`
- 🇩🇪 Deutsch: `README_de.md`
- 🇷🇺 Русский: `README_ru.md`

All localized READMEs contain a language switcher, the Mermaid architecture diagram, and a prominent legal-risk disclaimer.

## Quick Start

1. Install AstrBot v4.29.x, SnowLuma, and (optionally) Ollama.
2. Back up the target AstrBot directory.
3. Apply the files in `overlay/astrbot/` to the matching AstrBot paths.
4. Copy the custom plugins to AstrBot's `data/plugins/`.
5. Replace every `YOUR_*` placeholder.
6. Configure Windows accounts, ACLs, the Broker token, TOTP, and scheduled tasks.
7. Start with a test QQ account; verify ACLs and the Broker before any real use.
8. Use `config.lite.example.json` if you have no local GPU/Ollama.

## Known Limitations and Residual Risks

- **Compromised phone / hijacked TOTP:** the Broker can verify possession of a valid TOTP secret, but it cannot prove that the human approving is the legitimate owner. If an attacker controls the unlocked phone, authenticator seed, or synced authenticator account, they can approve actions. TOTP protects against automated scripts, prompt mistakes, and a stolen QQ account alone — not a compromised physical device.
- **In-memory replay cache:** the TOTP replay ledger resets when the Broker restarts; a restart inside the same 30-second TOTP window remains a documented residual risk.
- **Coverage gaps:** no equal TOTP enforcement for images, voice, video, or Shell execution; no Windows physical-confirmation dialog; third-party plugin side effects are outside the trust boundary.
- **Unofficial QQ protocol:** account restrictions and permanent bans remain possible. There is no code-level fix; only migration to an officially permitted API can remove this risk.

## Legal and Compliance Notice

- This repository contains overlay modifications based on AstrBot and is distributed under **AGPL-3.0**. You must comply with its source-code availability obligations; **closed-source commercial use is prohibited**.
- This is **not** an official Tencent, QQ, AstrBot, or SnowLuma project and is not affiliated with or endorsed by them.
- The software is provided **“AS IS”**, without warranty. The developers and contributors disclaim direct, indirect, incidental, special, consequential, and joint and several liability to the maximum extent permitted by law.
- You are solely responsible for complying with platform terms, local law, and all dependency licenses.

> **Again: use a test account. The unofficial QQ protocol can get accounts permanently banned. Do not connect a primary account.**

## Verification

- Local tests: `11 passed`
- Security design: [SECURITY.md](SECURITY.md)
- CI workflow: [`.github/workflows/security-tests.yml`](.github/workflows/security-tests.yml)
- License: [LICENSE](LICENSE)
