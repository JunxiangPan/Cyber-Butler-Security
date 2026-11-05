# Cyber-Butler Security (CBS)


## 한눈에 보는 상태

| 구성 요소 | 상태 | 비고 |
|---|---|---|
| SCM 서비스, SQLite 읽기/쓰기, Job Object | ✅ | |
| TOTP/승인 브로커 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| WFP 아웃바운드 차단 — 감사 전용 | ⚠️ | |
| OTP Mailer 8766 / AuxRuntime 5099 | ✅ | |
| 6199 AgentProtocol 어댑터 — 수동 구성 필요 | ❌ | |
| Light 등급 — 실기 설치 통과, 격리 약함 | ✅ | |
자체 호스팅 LLM 에이전트를 위한 방어적 제어 평면입니다.

## 빠른 시작

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAgentRuntime`; port 6185 must listen.

## High 아키텍처: 네이티브 Windows SCM 서비스

AgentRuntime은 `CyberButlerSvc` 아래에서 네이티브 SCM 서비스 `CyberButlerAgentRuntime`으로 실행됩니다. 바이너리는 ACL로 보호되고 대화형 로그온은 거부되며 Job Object가 자식 프로세스 트리를 관리합니다.

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AgentRuntime\data\logs\service-agentruntime.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## 이 릴리스의 상태

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

## 포트

```text
6185  AgentRuntime SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  AuxRuntime
6199  AgentRuntime AgentProtocol adapter (dynamic; not a CBS service)
```

## 알려진 제한

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light는 실기에서 설치에 성공했지만 격리는 High보다 약합니다. v1.6.2는 클린 VM 검증이 없습니다. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## 문서

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199는 CBS/AgentRuntime의 시스템 서비스가 아니며, AgentRuntime AgentProtocol 어댑터를 구성하고 활성화한 뒤 동적으로 열립니다.

legacy S4U 예약 작업 경로는 폐기되었습니다. AgentRuntime을 작업 스케줄러 작업으로 등록하지 마세요.

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

