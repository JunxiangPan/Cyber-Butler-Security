from pathlib import Path
import shutil

base = Path('docs')
legacy = base / '40-history/legacy-readmes'
legacy.mkdir(parents=True, exist_ok=True)
for f in ['README.md','README_en.md','README_zh.md','README_de.md','README_es.md','README_fr.md','README_ja.md','README_ko.md','README_ru.md']:
    p = Path(f)
    if p.exists():
        shutil.copy2(p, legacy / f)

(base / '20-operations/ports-and-adapters.md').write_text("""# Ports and adapters

| Port | Owner | Meaning |
|---|---|---|
| 6185 | SCM service `CyberButlerAgentRuntime` | AgentRuntime WebUI/API |
| 18090 | SYSTEM task `AgentRuntime TOTP Broker` | local approval/TOTP broker |
| 8765 | desktop task `Cyber-Butler Web UI Services` | CBS dashboard |
| 8766 | desktop task `Cyber-Butler OTP Mailer` | email OTP delivery |
| 5099 | desktop task `AuxRuntime Startup` | AuxRuntime WebUI |
| 6199 | AgentRuntime AgentProtocol adapter | **dynamic**, only after adapter configuration |

## 6199 is not a system service

`6199` is created dynamically by AgentRuntime's AgentProtocol adapter after the adapter is configured and enabled. It is not installed by CBS and must not be expected to listen before that configuration.

## Verification

```powershell
Get-NetTCPConnection -State Listen |
  Where-Object { $_.LocalPort -in 6185,18090,8765,8766,5099,6199 }
```
""", encoding='utf-8')

(base / 'README.md').write_text("""# Cyber-Butler Security documentation

## Languages

- [English](<../README_en.md>)
- [中文](<../README_zh.md>)
- [Deutsch](<../README_de.md>)
- [Español](<../README_es.md>)
- [Français](<../README_fr.md>)
- [日本語](<../README_ja.md>)
- [한국어](<../README_ko.md>)
- [Русский](<../README_ru.md>)

## Start here

1. [Project overview](00-overview/project-overview.md)
2. [Quick start](00-overview/quickstart.md)
3. [SCM architecture](00-overview/architecture-scm.md)
4. [Defense layers](10-security/defense-layers.md)
5. [Known limitations](10-security/known-limitations.md)
6. [Ports and adapters](20-operations/ports-and-adapters.md)
7. [Troubleshooting](20-operations/troubleshooting.md)
8. [Incident history](40-history/incidents/s4u-retirement.md)

## Canonical status

[status-v1.6.2.json](_data/status-v1.6.2.json) is the single fact source. Every language README links here.

## Current release

v1.6.2-rc2: AgentRuntime is a native SCM service (`CyberButlerAgentRuntime`) under `CyberButlerSvc`; 6185/18090/8765/8766/5099 are verified on the host. WFP remains audit-only; 6199 is a dynamic AgentProtocol adapter port; Light has no real-machine acceptance.
""", encoding='utf-8')

def section(lang):
    """Section.
    
    Args:
        lang: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return {
      'en': ('# Cyber-Butler Security (CBS)', 'A defensive control plane for self-hosted LLM agents.'),
      'zh': ('# Cyber-Butler Security（CBS）', '面向自托管 LLM 智能体的防御性安全控制面。'),
      'de': ('# Cyber-Butler Security (CBS)', 'Eine defensive Kontrollebene für selbst gehostete LLM-Agenten.'),
      'es': ('# Cyber-Butler Security (CBS)', 'Plano de control defensivo para agentes LLM autoalojados.'),
      'fr': ('# Cyber-Butler Security (CBS)', 'Plan de contrôle défensif pour agents LLM auto-hébergés.'),
      'ja': ('# Cyber-Butler Security (CBS)', 'セルフホスト型 LLM エージェント向けの防御的コントロールプレーン。'),
      'ko': ('# Cyber-Butler Security (CBS)', '자체 호스팅 LLM 에이전트를 위한 방어적 제어 평면입니다.'),
      'ru': ('# Cyber-Butler Security (CBS)', 'Защитная плоскость управления для самостоятельно размещённых LLM-агентов.')
    }[lang]

labels = {
 'en': {'quick':'Quick start','arch':'High architecture: native Windows SCM service','status':'Status','ports':'Ports','docs':'Documentation','limits':'Known limitations','state':'State of this release'},
 'zh': {'quick':'快速开始','arch':'High 架构：原生 Windows SCM 服务','status':'当前状态','ports':'端口','docs':'文档','limits':'已知限制','state':'本版本状态'},
 'de': {'quick':'Schnellstart','arch':'High-Architektur: nativer Windows-SCM-Dienst','status':'Status','ports':'Ports','docs':'Dokumentation','limits':'Bekannte Grenzen','state':'Stand dieser Version'},
 'es': {'quick':'Inicio rápido','arch':'Arquitectura High: servicio SCM nativo de Windows','status':'Estado','ports':'Puertos','docs':'Documentación','limits':'Limitaciones conocidas','state':'Estado de esta versión'},
 'fr': {'quick':'Démarrage rapide','arch':'Architecture High : service SCM Windows natif','status':'État','ports':'Ports','docs':'Documentation','limits':'Limites connues','state':'État de cette version'},
 'ja': {'quick':'クイックスタート','arch':'High アーキテクチャ: ネイティブ Windows SCM サービス','status':'状態','ports':'ポート','docs':'ドキュメント','limits':'既知の制限','state':'このリリースの状態'},
 'ko': {'quick':'빠른 시작','arch':'High 아키텍처: 네이티브 Windows SCM 서비스','status':'상태','ports':'포트','docs':'문서','limits':'알려진 제한','state':'이 릴리스의 상태'},
 'ru': {'quick':'Быстрый старт','arch':'Архитектура High: собственная служба Windows SCM','status':'Статус','ports':'Порты','docs':'Документация','limits':'Известные ограничения','state':'Состояние этого выпуска'}
}

summary = {
 'en':'AgentRuntime runs as the native SCM service `CyberButlerAgentRuntime` under `CyberButlerSvc`. The service binary is ACL-locked, interactive logon is denied, and a Job Object owns the child tree.',
 'zh':'AgentRuntime 以 `CyberButlerSvc` 运行原生 SCM 服务 `CyberButlerAgentRuntime`。服务二进制 ACL 已锁定，禁止交互登录，并用 Job Object 接管子进程树。',
 'de':'AgentRuntime läuft als nativer SCM-Dienst `CyberButlerAgentRuntime` unter `CyberButlerSvc`. Die Binärdatei ist ACL-geschützt, interaktive Anmeldung ist gesperrt und ein Job Object steuert den Prozessbaum.',
 'es':'AgentRuntime se ejecuta como servicio SCM nativo `CyberButlerAgentRuntime` con `CyberButlerSvc`. El binario está protegido por ACL, el inicio de sesión interactivo está denegado y un Job Object controla el árbol de procesos.',
 'fr':'AgentRuntime s’exécute comme service SCM natif `CyberButlerAgentRuntime` sous `CyberButlerSvc`. Le binaire est protégé par ACL, la connexion interactive est refusée et un Job Object gère l’arbre de processus.',
 'ja':'AgentRuntime は `CyberButlerSvc` の下でネイティブ SCM サービス `CyberButlerAgentRuntime` として実行されます。バイナリは ACL で保護され、対話ログオンは拒否され、Job Object が子プロセス ツリーを管理します。',
 'ko':'AgentRuntime은 `CyberButlerSvc` 아래에서 네이티브 SCM 서비스 `CyberButlerAgentRuntime`으로 실행됩니다. 바이너리는 ACL로 보호되고 대화형 로그온은 거부되며 Job Object가 자식 프로세스 트리를 관리합니다.',
 'ru':'AgentRuntime работает как собственная служба SCM `CyberButlerAgentRuntime` под `CyberButlerSvc`. Бинарный файл защищён ACL, интерактивный вход запрещён, а Job Object управляет деревом процессов.'
}
for lang in labels:
    title, desc = section(lang)
    l = labels[lang]
    fname = 'README.md' if lang == 'en' else f'README_{lang}.md'
    text = f"""{title}

{desc}

## {l['quick']}

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAgentRuntime`; port 6185 must listen.

## {l['arch']}

{summary[lang]}

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AgentRuntime\\data\\logs\\service-agentruntime.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## {l['state']}

| Item | State |
|---|---|
| SCM service 6185 | verified on host |
| SQLite write probe | passed |
| Broker 18090 | listening |
| WebUI 8765 / OTP 8766 | listening |
| AuxRuntime 5099 | listening |
| WFP | audit-only, enforce not enabled |
| 6199 | dynamic AgentProtocol adapter port, not a service |
| Light / clean VM | not accepted yet |

Canonical source: [`docs/_data/status-v1.6.2.json`](docs/_data/status-v1.6.2.json).

## {l['ports']}

```text
6185  AgentRuntime SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  AuxRuntime
6199  AgentRuntime AgentProtocol adapter (dynamic; not a CBS service)
```

## {l['limits']}

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light has no real-machine acceptance, and v1.6.2-rc2 has no clean-VM acceptance. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## {l['docs']}

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)
"""
    Path(fname).write_text(text, encoding='utf-8')

Path('docs/README.md').write_text((Path('docs/README.md').read_text(encoding='utf-8') if Path('docs/README.md').exists() else '# Documentation index\n\nSee [documentation index](README.md).\n'), encoding='utf-8')
print('readmes written')
