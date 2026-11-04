# Cyber-Butler Installer (v1.6.3)

> v1.6.1 status, incomplete work, and non-guarantees: [../docs/STATUS_v1.6.1.md](../docs/STATUS_v1.6.1.md).


One installer, three declarative profiles, one pipeline.

## Current block status

Block 1 through Block 7 are implemented:

- `lib/Installer.Tier.ps1` and the three profiles
- `Install-CyberButler.ps1` end-to-end skeleton with `-PlanOnly`, `-Resume`,
  `-Repair`, `-Rollback`
- `lib/Installer.Preflight.ps1` read-only environment snapshot
- `lib/Installer.Journal.ps1` state, backups, resume, reverse actions
- `lib/Installer.Accounts.ps1` service-account lifecycle
- `lib/Installer.Acl.ps1` ACL lifecycle
- `lib/Installer.Firewall.ps1` firewall-rule lifecycle
- `lib/Installer.Totp.ps1` TOTP material and vault ACL lifecycle
- `lib/Installer.Secrets.ps1` DPAPI secrets and `local-overlay.json`
- `lib/Installer.Services.ps1` scheduled tasks and port health
- `lib/Installer.Core.ps1` real download, SHA-256, extraction, venv, overlay merge
- `core-sources.json` pinned AstrBot/SnowLuma source descriptors
- `lib/Installer.Diagnostics.ps1` eight-item defense checklist
- `lib/Installer.Report.ps1` JSON/Markdown install reports
- `lib/totp_material.py` TOTP/QR/recovery generator (no secret output)

Core deployment is implemented with pinned official AstrBot and SnowLuma
URLs/SHA-256 in `core-sources.json`. Local packages can be supplied with
`-AstrBotPackage` / `-SnowLumaPackage`. Real privileged execution still
remains a clean-Windows-VM acceptance step.

## Visual installer

Launch the WPF front-end from an elevated interactive desktop:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA `
  -File .\installer\CyberButler.Installer.GUI.ps1
```

The GUI collects the install path, tier, owner QQ, WebUI bind, optional
personal-plugins path, and an optional API-key file. It can run a read-only
preflight and then runs the privileged installer as a hidden child process.
Approval tokens are supplied only after the explicit GUI approval checkbox;
TOTP enrollment opens a WPF dialog with the QR image and recovery codes.

The `-SelfTest` switch loads the XAML without showing the window; it is used by
Pester only. The GUI must be started from an elevated session; the launcher
requests UAC when needed.


## Main installer

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\installer\Install-CyberButler.ps1 `
  -Tier Medium -NonInteractive `
  -InstallPath C:\CyberButler `
  -OwnerQQ <owner-qq> `
  -JournalRoot C:\ProgramData\CyberButler\installer\state `
  -ReportDirectory C:\ProgramData\CyberButler\installer-report
```

Flow:

```text
Preflight -> Plan/APPROVE PLAN -> Core dry-run placeholder ->
Accounts -> ACL -> Firewall -> TOTP -> Secrets -> Services ->
Diagnostics -> install-report.json / install-report.md
```

- Every security step requires its own approval token.
- `-NonInteractive` stops with exit 10 if a token is missing.
- Any failed step triggers journal rollback and writes a manual-recovery path.
- `-PlanOnly` stops after preflight and plan and never calls an `Invoke-*`.
- `-Resume -StatePath <state.json>` continues from the last unfinished step.
- `-Repair` runs diagnostics and writes a report without reinstalling.
- Reports contain status, approval records, journal path, and manual/failure
  items; they never contain secret values.

## Diagnostics and report

Diagnostics is read-only and reports eight items:

```text
双账户隔离 / TOTP 审批 / Router fail-closed / Web UI 绑定
API Key 保护 / TOTP 保险箱隔离 / 审计 / 防火墙
```

Each item is `ENABLED`, `PARTIAL`, `MANUAL`, or `FAILED` with a reason. Reports
are written as `install-report.json` and `install-report.md`.



## Preflight

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command `
  "& { .\installer\lib\Installer.Common.ps1; .\installer\lib\Installer.Tier.ps1; .\installer\lib\Installer.Preflight.ps1; Get-CyberButlerPreflight -InstallPath C:\CyberButler -OutputPath .\preflight.json }"
```

Preflight is read-only and writes only the requested `preflight.json`.

### Existing installation state

`Get-CyberButlerExistingState` is the single classifier used by both Preflight
and `-PlanOnly`:

```text
None       no VERSION file
Legacy     VERSION exists, installer/install-state.json is absent
Installed  VERSION and installer/install-state.json both exist
```

`has_existing_install` is true for both `Legacy` and `Installed`. A successful
install or isolation migration writes `installer/install-state.json`; a legacy
v1.5.x tree without that marker is shown as `Legacy`, not `Installed`.

## Journal

```powershell
# Create a journal for the current run
$journal = New-CyberButlerJournal -Root C:\ProgramData\CyberButler\installer\state `
  -InstallPath C:\CyberButler -Tier Medium

# Resume reports the first unfinished step
Get-CyberButlerResumeStep -Journal (Read-CyberButlerJournal -StatePath $journal.StatePath)

# Roll back reverse actions in reverse order
Invoke-CyberButlerRollback -Journal $journal
```

Reverse actions supported by Block 2:

- `delete-created-directory`
- `restore-file`
- `restore-acl`
- `restore-scheduled-task`

The ACL and scheduled-task handlers require elevation in production. Tests
inject handlers for those privileged actions.

## Block 3 safety primitives

Each module exposes the four-part contract:

```text
Test-*     current state / already satisfied
Invoke-*   approved change, with journal backup
Assert-*   post-change verification
Undo-*     reverse action
```

All `Invoke-*` functions:

- run `Test-*` first and skip when already satisfied
- return `needs_approval` (exit 10) without changing anything unless the exact
  `APPROVE ACCOUNT`, `APPROVE ACL`, `APPROVE FIREWALL`, `APPROVE TOTP`,
  `APPROVE SECRETS`, or `APPROVE SERVICES` token is supplied
- return `plan` without changing anything under `-PlanOnly`
- call `Assert-*` after every change
- call `Undo-*` and mark the journal step failed when `Assert-*` fails

Accounts never delete a pre-existing account. ACL and firewall tests use
handler injection so the test suite does not modify the host.

## Block 4 safety material

- TOTP material is generated by `lib/totp_material.py`; it writes the DPAPI
  secret, QR image, and recovery codes without printing secret material.
- TOTP requires both `APPROVE TOTP` and explicit `-Scanned` /
  `-RecoverySaved` confirmation.
- The vault ACL allows SYSTEM, Administrators, and the nominated reader.
  In isolation mode the separate AstrBot service account is denied. In
  single-account mode the AstrBot identity is the administrator, so the deny
  rule is skipped to avoid locking out the installer; reader and AstrBot must
  still differ.
- Secrets are DPAPI-protected before they touch disk. Tests use fake values and
  assert the journal/result never contain them.
- Services use `restore-scheduled-task`, `delete-created-scheduled-task`, and
  `stop-created-process` reverse actions; existing task XML is restored before
  newly started processes are stopped.
- No Block 4 test registers a real scheduled task, starts a real service, or
  reads a real DPAPI secret.


## Plan only

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\installer\Install-CyberButler.ps1 `
  -PlanOnly -Tier Medium -InstallPath C:\CyberButler
```

Default:

```text
Tier = Medium
EnableIsolation = false
WebUIBind = Loopback
```

Rules:

- `High` requires `-EnableIsolation:$true`
- `Light` requires `-AcceptLowerSecurity`
- `High` rejects `-WebUIBind LAN`
- `Medium`/`Light` allow LAN only with a blocking `APPROVE LAN`
- `Medium + Isolation` and `Light + Isolation` keep their labels and are not
  promoted to High

## Block 3 integration validation (required before v1.6.0 release)

The handler-injection suite does not prove the privileged paths. Before release,
run the real account/ACL/firewall paths on a clean Windows 11 Pro VM and record:

- the service account can be created and can log on as the intended service
  principal;
- after the ACL is applied, AstrBot starts and can read/write only its intended
  data/workspace paths;
- with the firewall rules active, ports 6185, 18090, and 8765 remain reachable
  only from the intended loopback/Tailscale boundary.

## Isolation migration

`Migrate-EnableIsolation.ps1` supports:

```powershell
.\installer\Migrate-EnableIsolation.ps1 -PlanOnly
.\installer\Migrate-EnableIsolation.ps1 -Apply
.\installer\Migrate-EnableIsolation.ps1 -Verify
.\installer\Migrate-EnableIsolation.ps1 -Rollback
```

`-Apply` requires `APPROVE MIGRATE-ISOLATION`; `-NonInteractive` without it
exits 10. SnowLuma and the TOTP Broker are never migrated. Data is not copied;
rollback restores task XML, ACLs, and secret references only.

## Prerequisites

Preflight accepts a real Python 3.10-3.13, or marks
`python_needs_bundle=true` when the system Python is 3.14+ or unavailable.
In that case the installer downloads Python 3.13.17 into `<InstallPath>\.python`
before Core Deploy. The selected absolute path, not the system `python`, is used
for `python -m venv`.

`-PythonPackage <official .exe>` is supported for offline installation.
The Python installer may write a per-user uninstall entry; the journal records
the discovered registry key for the future uninstaller.

### System Python too new

A system Python 3.14+ no longer blocks the install. Preflight marks
`python_needs_bundle=true`, PlanOnly shows the bundling step, and after
`APPROVE PLAN` the installer downloads Python 3.13.17 into
`<InstallPath>\.python`.

Messages used by PlanOnly:

- System Python 3.14+:
  `System Python is 3.14+; installer will download Python 3.13 into <InstallPath>\.python.`
- No system Python:
  `No compatible system Python was found; installer will download Python 3.13 into <InstallPath>\.python.`
- Both add:
  `Supply -PythonPackage <path> for offline installation.`

The bundled Python is not added to PATH and does not replace system Python.
Offline installs can pass the official installer directly:

```powershell
-PythonPackage .\python-3.13.17-amd64.exe
```

The SHA-256 comes from `installer/core-sources.json`; a mismatch stops the
install and does **not** fall back to system Python. Only network/download or
installer-execution failures may fall back to an already compatible system
Python.

The Python installer may write a per-user uninstall entry. The journal records
the discovered registry key. A future `Uninstall-CyberButler.ps1` must remove
the `.python` directory, call the pinned installer with `/uninstall /quiet`,
and clean up that registry entry.

## Core deployment

`lib/Installer.Core.ps1` performs the real core stage:

```text
download -> SHA-256 verify -> extract -> create directories ->
venv + requirements -> overlay merge -> assert
```

- `None` installs a fresh tree.
- `Legacy` / `Installed` merges code over the existing tree, excludes
  `data`, `.venv`, SnowLuma `data`/`config`/`logs`, and preserves all existing
  data and extra files.
- New directories and replaced files are journaled; a failure removes the
  staging tree and any directories created by the failed fresh install.
- A SHA-256 mismatch aborts before target directories are created.

Source descriptors live in `installer/core-sources.json` with pinned official
AstrBot v4.29.3 and SnowLuma v2.2.1 URLs/SHA-256. Downloads support timeout,
retry, optional `-ResumeDownload`, and a GitHub-specific failure hint. Use
`-AstrBotPackage` / `-SnowLumaPackage` for local VM packages when needed.

## Troubleshooting / 常见问题

> **脱敏与安全**
>
> 本文档只使用占位符：`<YourUsername>`、`<YourQQ>`、`<YourAPIKey>`、`<YourSmtpAuthCode>`、`<YourTOTPSecret>`。
> 不要把真实的 API Key、SMTP 授权码、TOTP Secret 或恢复码发送给 AI、聊天工具、issue 或任何公网服务。
> TOTP Secret 和恢复码一旦泄露，攻击者可以绕过审批。请本地离线保存。

### 1. Python 环境问题（最常见的坑）

系统 Python 支持：

```text
Python 3.10 - 3.13
推荐 3.13.17
```

如果系统 Python 是 3.14 / 3.15，安装器不会强迫你降级：
Preflight 会标记 `python_needs_bundle=true`，在 `APPROVE PLAN` 之后自动下载
Python 3.13.17 到 `<InstallPath>\.python`，并用它创建 AstrBot venv。

旧版本或手动创建的 venv 如果直接使用 3.15，pip 仍可能报：

```text
Requires-Python >=3.9,<3.15
No matching distribution found
```

遇到这种情况请使用 v1.6.0 的 bundled Python，或通过
`-PythonPackage <官方 Python 3.13.17 .exe>` 离线提供。

安装 Python 时必须勾选：

```text
Add python.exe to PATH
```

验证：

```powershell
where.exe python
python -c "import sys; print(sys.executable); print(sys.version)"
```

如果 `where.exe python` 第一条是：

```text
C:\Users\<YourUsername>\AppData\Local\Microsoft\WindowsApps\python.exe
```

这是 Windows Store 的 App Execution Alias，不是可用的 Python。处理方式：

1. 打开 `设置 -> 应用 -> 高级应用设置 -> 应用执行别名`。
2. 关闭 `python.exe` 和 `python3.exe` 的别名。
3. 确认真实 Python 出现在 `where.exe python` 的第一条。
4. 重新打开 PowerShell 后再运行安装器。

Preflight 会检查真实可执行性和版本；只检查 `python --version` 不够。

隔离 Python 安装到 `<InstallPath>\.python`，不会替换系统 Python。它会写
per-user uninstall 注册项；安装 journal 会记录发现的注册表键，未来
`Uninstall-CyberButler.ps1` 必须删除 `.python` 目录并调用
`python-3.13.17-amd64.exe /uninstall /quiet`，同时清理该注册项。

### 2. `-File` 与 `-ApiKey` / `-SmtpSecret` 的参数问题

旧版本把参数声明成 `[SecureString]` 时，`powershell -File` 会把它序列化成字符串，可能报：

```text
Cannot convert value ... to type System.Security.SecureString
```

当前安装器接受明文或 `SecureString`，推荐直接在 PowerShell 中调用：

```powershell
$apiKey = ConvertTo-SecureString '<YourAPIKey>' -AsPlainText -Force
$smtp   = ConvertTo-SecureString '<YourSmtpAuthCode>' -AsPlainText -Force

.\installer\Install-CyberButler.ps1 `
  -Tier Medium `
  -OwnerQQ <YourQQ> `
  -ApiKey $apiKey `
  -SmtpSecret $smtp
```

也可以使用明文参数：

```powershell
.\installer\Install-CyberButler.ps1 -Tier Medium -OwnerQQ <YourQQ> -ApiKey '<YourAPIKey>'
```

明文参数可能出现在进程命令行中；能交互输入时优先不传参数，等待安装器提示：

```text
Please enter your DeepSeek API Key (leave empty to skip):
Please enter your 163 SMTP Auth Code (leave empty to skip):
```

留空的 secret 会在报告中标记为 `PARTIAL (skipped by user)`，不会让安装在中途直接崩溃。

#### `stdin is not interactive`

如果 `powershell -File` 下提示出现后按回车没有反应，或者 stdin 被重定向，
安装器不会继续等待。它会快速失败并打印：

```text
stdin is not interactive; pass -ApiKey / -SmtpSecret instead
```

此时改用明文参数：

```powershell
.\installer\Install-CyberButler.ps1 `
  -Tier Medium `
  -OwnerQQ <YourQQ> `
  -ApiKey '<YourAPIKey>' `
  -SmtpSecret '<YourSmtpAuthCode>'
```

明文参数可能出现在进程命令行中；如果终端本身可交互，仍可只运行脚本并按提示输入。
不要在聊天、issue 或日志中粘贴真实 API Key / SMTP 授权码。

### 3. 下载慢或 GitHub 连接失败

Core 下载和 `pip install` 在普通网络下可能需要 5–10 分钟，具体取决于 GitHub、PyPI 和杀毒软件扫描速度。

正常会看到：

```text
CORE downloading ...
CORE downloaded ...
CORE extracting ...
CORE installing dependencies (this may take several minutes)...
CORE pip log: C:\CyberButler\installer-report\pip-install.log
```

不要因为暂时没有新行就强行 `Ctrl+C`。pip 的完整输出同时写入：

```text
C:\CyberButler\installer-report\pip-install.log
```

如果 GitHub 连不上，可以手动下载官方包，然后使用本地包参数：

```powershell
.\installer\Install-CyberButler.ps1 `
  -Tier Medium `
  -OwnerQQ <YourQQ> `
  -AstrBotPackage .\AstrBot-4.29.3.zip `
  -SnowLumaPackage .\SnowLuma-v2.2.1-win-x64.zip `
  -AstrBotSha256 <AstrBotSHA256> `
  -SnowLumaSha256 <SnowLumaSHA256>
```

如果系统 Python 不可用或版本过高，可同时指定：

```powershell
-PythonPackage .\python-3.13.17-amd64.exe
```

本地 Python 包必须是官方 installer `.exe`，并会按 `core-sources.json`
中的 SHA-256 校验。校验失败不会回退，也不会安装。

官方 URL 和 SHA-256 固定在 `installer/core-sources.json`。下载源失败时，安装器会提示检查 DNS、代理/VPN 和防火墙，或改用本地包。

### 4. TOTP 绑定与 vault ACL

`APPROVE TOTP` 之后，终端会打印：

- Base32 Secret
- 分组后的 Secret
- `otpauth://` URI
- 二维码路径
- 恢复码

二维码文件：

```text
C:\CyberButler\tools\totp-vault\totp_qr.png
```

如果终端内容被截断，可以直接打开二维码扫描：

```powershell
Start-Process C:\CyberButler\tools\totp-vault\totp_qr.png
```

恢复码：

```powershell
Get-Content C:\CyberButler\tools\totp-vault\recovery_codes.txt
```

请立刻离线抄写恢复码。不要截图发到聊天工具，不要把 Secret 发给 AI 或任何在线服务。

如果遇到 TOTP vault 的“拒绝访问”，通常是 ACL 或旧规则导致的。用**管理员** PowerShell 临时恢复访问权：

```powershell
takeown /F "C:\CyberButler\tools\totp-vault" /R /A
icacls "C:\CyberButler\tools\totp-vault" /grant "BUILTIN\Administrators:(OI)(CI)F" /T
```

读取或重新绑定后，必须重新运行安装器恢复受限 ACL。上面的 `icacls` 会让管理员组可读 TOTP 材料；这是排障操作，不是长期配置。TOTP vault 的最终目标是只允许 SYSTEM、Administrators 和指定 Reader，且不对当前安装用户添加 Deny。

如果 TOTP 已经生成但控制台没有显示 Secret，可以检查：

```text
totp_secret.dpapi
recovery_codes.txt
totp_qr.png
```

`totp_secret.dpapi` 是 DPAPI 加密的，不要把它复制到其他机器。二维码图片通常是最简单的本地恢复方式。

### 5. 计划任务注册失败：0x80070534

错误：

```text
Register-ScheduledTask : 账户名与安全标识间无任何映射完成
(15,8):UserId: 0x80070534
```

表示 `UserId` 不是当前机器可解析的账户。检查实际账户：

```powershell
whoami
$env:USERDOMAIN
$env:USERNAME
Get-LocalUser
Get-ScheduledTask -TaskName 'AstrBot Service' | Select-Object -ExpandProperty Principal
```

规则：

- Medium / Light 单账户：AstrBot Service 使用当前登录用户，principal 为 `Interactive`。
- High 隔离：AstrBot 使用原生 Windows 服务 `CyberButlerAstrBot`，运行账户为 `<YourComputer>\CyberButlerSvc`；服务由 SCM 托管，不再使用 S4U 计划任务。
- TOTP Broker 使用 `NT AUTHORITY\SYSTEM`。

安装器现在会打印：

```text
SERVICE registering <task> as <actual-user> (<logon-type>)
```

失败时错误也会包含实际 `UserId` 和 `LogonType`。

如果当前是微软在线账户，`whoami` 可能显示缩写或与显示名不同；使用 `whoami` 返回的完整 `DOMAIN\User`，不要使用裸显示名。必要时在安装器中显式传：

```powershell
-DesktopAccount '<YourComputer>\<YourUsername>'
```

High 模式应确认服务账户存在：

```powershell
Get-LocalUser -Name 'CyberButlerSvc'
```

不要为了绕过 0x80070534 而关闭 Defender 或把服务账户加入不必要的管理员组。

### 6. 安全门禁过严导致当前用户被锁

TOTP vault 使用 ACL 限制谁能读取 Secret。若更换账户、用另一个用户运行安装器，或保留了旧的 Deny ACE，可能出现：

```text
Access is denied
Test-Path : 拒绝访问
```

处理步骤：

1. 用管理员 PowerShell 确认当前身份：

```powershell
whoami
Get-Acl "C:\CyberButler\tools\totp-vault" | Format-List
```

2. 如果确实需要临时取回访问权：

```powershell
takeown /F "C:\CyberButler\tools\totp-vault" /R /A
icacls "C:\CyberButler\tools\totp-vault" /grant "BUILTIN\Administrators:(OI)(CI)F" /T
```

3. 读取 TOTP 材料或完成迁移后，重新运行：

```powershell
.\installer\Install-CyberButler.ps1 -Tier Medium -OwnerQQ <YourQQ>
```

4. 确认最终 ACL 不再 Deny 当前安装用户，且 Administrators 仍可管理。

安全警告：`takeown`/`icacls` 只是恢复管理访问，不能当作长期修复。恢复后应重新运行安装器，让 vault ACL 重新收紧。

### 7. Defender 与测试环境

不要提供或执行“永久关闭 Defender”的教程。若测试环境确实需要减少扫描干扰，只能在受控测试机上临时添加安装目录排除项，并在测试完成后立即移除。生产环境应保留 Defender 和审计。

### 安全提醒

- TOTP Secret 和恢复码只在本地离线保存。
- 不要把 Secret、恢复码、API Key 或 SMTP 授权码发送给 AI、聊天群、issue 或公网。
- 不要把 `totp_secret.dpapi` 复制到其他机器。
- 安装报告和日志不包含 secret 值；如果手动读取，请使用受控本地终端。

## Personal plugins (optional)

CBS 开源包只包含安全层插件。以下三个插件是个人定制插件，不随开源包发布：

```text
astrbot_plugin_private_companion
astrbot_plugin_livingmemory
astrbot_plugin_memorix
```

需要完整苏瑾言时，用 `-PersonalPluginsPath` 指定这三个插件的源目录：

```powershell
.\installer\Install-CyberButler.ps1 `
  -Tier Medium `
  -PersonalPluginsPath D:\qq苏瑾言大肥鱼\AstrBot\data\plugins
```

规则：

- 只接受上面三个目录；其它目录忽略并 WARN
- 每个插件必须包含 `main.py` 和 `metadata.yaml`
- 插件目录下的 `data/` 不复制
- 目标 `_conf_schema.json` 已存在时保留，不覆盖
- 未指定 `-PersonalPluginsPath` 时跳过，报告记录 `Personal plugins: skipped`
- `-Repair` 只检查目录和 `main.py`，不覆盖任何文件
- 插件文件按 SHA-256 幂等；相同文件跳过，不生成 `.bak`

### 从 v1.5.x 迁移

v1.5.x 通常安装在 `D:\qq苏瑾言大肥鱼`，v1.6.0 默认安装到 `C:\CyberButler`。这不是原地升级。

```text
旧安装：D:\qq苏瑾言大肥鱼\AstrBot\data\plugins
新安装：C:\CyberButler\AstrBot\data\plugins
```

安装时指定旧插件源：

```powershell
-PersonalPluginsPath "D:\qq苏瑾言大肥鱼\AstrBot\data\plugins"
```

旧安装的 `AstrBot/data/`（记忆、对话历史、数据库）不会自动迁移，需要手动处理。v1.6.0 目标目录已有个人插件时，不传 `-PersonalPluginsPath` 会保留现有插件。

## Manifest integration

`installer/` is included in the updater allowlist in `tools/update_core.py`.
It is not a runtime prefix, so `update_merge_core.is_runtime()` must stay false
for installer files. The package builder uses the Git index; once `installer/`
is committed, its files are included in `update-manifest.json`. This change
does not package or commit anything.

## Validation status

- 112 Pester tests pass.
- Real privileged execution paths are still pending clean Windows 11 Pro VM
  validation.
- `-Repair` is currently read-only diagnostics and does not perform security
  repairs.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command `
  "Invoke-Pester -Script .\installer\tests -PassThru"
```

Pester 3.4 is supported.
