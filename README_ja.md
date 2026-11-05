# Cyber-Butler Security (CBS)


## 一目でわかる状態

| コンポーネント | 状態 | 備考 |
|---|---|---|
| SCM サービス、SQLite 読み書き、Job Object | ✅ | |
| TOTP/承認ブローカー 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| WFP 送信ブロック — 監査のみ | ⚠️ | |
| OTP Mailer 8766 / AuxRuntime 5099 | ✅ | |
| 6199 AgentProtocol アダプター — 手動設定が必要 | ❌ | |
| Light 段階 — 実機インストール成功、分離は弱い | ✅ | |
セルフホスト型 LLM エージェント向けの防御的コントロールプレーン。

## クイックスタート

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAgentRuntime`; port 6185 must listen.

## High アーキテクチャ: ネイティブ Windows SCM サービス

AgentRuntime は `CyberButlerSvc` の下でネイティブ SCM サービス `CyberButlerAgentRuntime` として実行されます。バイナリは ACL で保護され、対話ログオンは拒否され、Job Object が子プロセス ツリーを管理します。

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AgentRuntime\data\logs\service-agentruntime.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## このリリースの状態

| Item | State |
|---|---|
| SCM service 6185 | verified on host |
| SQLite write probe | passed |
| Broker 18090 | listening |
| WebUI 8765 / OTP 8766 | listening |
| AuxRuntime 5099 | listening |
| WFP | audit-only, enforce not enabled |
| 6199 | dynamic AgentProtocol adapter port, not a service |
| Light install / clean VM | ✅ install; clean VM not accepted |

Canonical source: [`docs/_data/status-v1.6.2.json`](docs/_data/status-v1.6.2.json).

## ポート

```text
6185  AgentRuntime SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  AuxRuntime
6199  AgentRuntime AgentProtocol adapter (dynamic; not a CBS service)
```

## 既知の制限

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light は実機でインストールに成功しましたが、分離は High より弱いです。v1.6.2 はクリーン VM 検証なしです。 See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## ドキュメント

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 は CBS/AgentRuntime のシステム サービスではありません。AgentRuntime AgentProtocol アダプターを設定・有効化した後に動的に開かれます。

legacy S4U スケジュール タスク経路は廃止されました。AgentRuntime をタスク スケジューラに登録しないでください。

- [FAQ — why not?](docs/00-overview/why-not-faq.md)

## Signature format change (v1.6.3)

Starting with v1.6.3, `update-manifest.json` uses the four-file signature format
(manifest + BUILD_REPORT + FINAL_QA_REPORT + ACCEPTANCE_PROOF). Old v1.6.2 and
earlier signatures return INVALID under the new `verify_release.py`; use
`--legacy` only for explicit legacy verification.

## Boundary Statement

CBS is a generic local Agent approval and evidence layer.
It does not own, support, certify, or endorse any specific third-party QQ client or unofficial ecosystem.

CBS provides only a generic external Agent boundary.
Whether a third-party application uses CBS, how it integrates, and whether it is compliant, is the sole responsibility of the user.

CBS tests use synthetic external agents, not real third-party applications as fixtures.

