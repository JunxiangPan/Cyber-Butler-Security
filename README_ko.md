# Cyber-Butler Security (CBS)

자체 호스팅 LLM 에이전트를 위한 방어적 제어 평면입니다.

## 빠른 시작

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAstrBot`; port 6185 must listen.

## High 아키텍처: 네이티브 Windows SCM 서비스

AstrBot은 `CyberButlerSvc` 아래에서 네이티브 SCM 서비스 `CyberButlerAstrBot`으로 실행됩니다. 바이너리는 ACL로 보호되고 대화형 로그온은 거부되며 Job Object가 자식 프로세스 트리를 관리합니다.

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AstrBot\data\logs\service-astrbot.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## 이 릴리스의 상태

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

## 포트

```text
6185  AstrBot SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  SnowLuma
6199  AstrBot OneBot adapter (dynamic; not a CBS service)
```

## 알려진 제한

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light has no real-machine acceptance, and v1.6.2-rc2 has no clean-VM acceptance. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## 문서

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199는 CBS/AstrBot의 시스템 서비스가 아니며, AstrBot OneBot 어댑터를 구성하고 활성화한 뒤 동적으로 열립니다.

S4U 예약 작업 경로는 폐기되었습니다. AstrBot을 작업 스케줄러 작업으로 등록하지 마세요.
