# Cyber-Butler Security (CBS)

セルフホスト型 LLM エージェント向けの防御的コントロールプレーン。

## クイックスタート

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAstrBot`; port 6185 must listen.

## High アーキテクチャ: ネイティブ Windows SCM サービス

AstrBot は `CyberButlerSvc` の下でネイティブ SCM サービス `CyberButlerAstrBot` として実行されます。バイナリは ACL で保護され、対話ログオンは拒否され、Job Object が子プロセス ツリーを管理します。

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AstrBot\data\logs\service-astrbot.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## このリリースの状態

| Item | State |
|---|---|
| SCM service 6185 | verified on host |
| SQLite write probe | passed |
| Broker 18090 | listening |
| WebUI 8765 / OTP 8766 | listening |
| SnowLuma 5099 | listening |
| WFP | audit-only, enforce not enabled |
| 6199 | dynamic OneBot adapter port, not a service |
| Light / clean VM | not accepted yet |

Canonical source: [`docs/_data/status-v1.6.2.json`](docs/_data/status-v1.6.2.json).

## ポート

```text
6185  AstrBot SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  SnowLuma
6199  AstrBot OneBot adapter (dynamic; not a CBS service)
```

## 既知の制限

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light has no real-machine acceptance, and v1.6.2 has no clean-VM acceptance. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## ドキュメント

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 は CBS/AstrBot のシステム サービスではありません。AstrBot OneBot アダプターを設定・有効化した後に動的に開かれます。

S4U スケジュール タスク経路は廃止されました。AstrBot をタスク スケジューラに登録しないでください。
