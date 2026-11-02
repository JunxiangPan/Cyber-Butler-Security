# v1.6.1 Troubleshooting / 常见故障排查

> Applies to the v1.6.1 package. If a page disagrees, this troubleshooting
> guide and [STATUS_v1.6.1.md](STATUS_v1.6.1.md) win.

## 1. `QQ challenge send failed` / `6199` is not `Established`

**Symptoms**

```text
Broker returns: {"ok":false,"status":"denied","error":"QQ challenge send failed"}
6199 only has Listen, no Established
AstrBot log: aiocqhttp.exceptions.ApiNotAvailable
```

**Cause**

AstrBot may be running, but SnowLuma is not injected into QQ or has not
connected its OneBot reverse WebSocket.

**Fix**

1. Start QQNT and complete login. National-network identity verification is a
   QQ requirement and cannot be bypassed by CBS.
2. Ensure SnowLuma starts **after** QQ. The v1.6.1 `start-snowluma.ps1` waits for
   QQ; use the packaged `SnowLuma Startup` task instead of starting SnowLuma by
   hand.
3. Auto-injection must be enabled:

   ```powershell
   $env:SNOWLUMA_HOOK_AUTOLOAD = 'true'
   ```

   The packaged `start-snowluma.ps1` sets this for its child process.
4. Confirm SnowLuma logs:

   ```powershell
   Get-Content 'C:\CyberButler\SnowLuma\logs\startup-snowluma.out.log' -Tail 40
   ```

   Expect:

   ```text
   hook auto-load enabled: every discovered QQ process will be injected
   Hook login detected
   Hook pipe connected
   OneBot.WS-Client ... connected ws://127.0.0.1:6199/ws
   ```

5. Check:

   ```powershell
   Get-NetTCPConnection -LocalPort 6199 -ErrorAction SilentlyContinue |
     Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess
   ```

   `Established` is required. If it is missing, open SnowLuma at
   `http://127.0.0.1:5099`, confirm the `CBS-AstrBot` WS client exists, and
   refresh/reload the QQ injection.

### WebUI 邮箱与 SMTP 字段

CBS WebUI 8765 使用管理员邮箱 + 邮件 OTP；AstrBot 6185 使用用户名/密码。

| 字段 | 说明 |
|---|---|
| WebUI 邮箱 | 管理员邮箱，用于登录 CBS WebUI、接收 TOTP 审批和告警；不是机器人 QQ |
| SMTP host | 发信服务器，如 `smtp.163.com`、`smtp.gmail.com` |
| SMTP port | 当前邮件组件使用隐式 SSL，填 `465`；`587`/STARTTLS 未支持 |
| SMTP 授权码 | 服务商生成的授权码/应用专用密码，不是邮箱登录密码；DPAPI 加密保存 |
| SMTP 用户 | 通常与 WebUI 邮箱相同 |

缺失时：WebUI 登录 OTP 和 TOTP 邮件发不出去，Broker 返回 HTTP 503，Dashboard 显示红色 Banner。

## 1.1 CBS WebUI asks for an email but there is no sign-up

The CBS WebUI at `http://127.0.0.1:8765` uses a **preconfigured administrator
email + email OTP**, not self-registration. The installer now exposes:

```text
WebUI email
SMTP auth code
```

for the 163 SMTP defaults (`smtp.163.com:465`, user = the WebUI email,
recipient = the same email). If those fields are empty, the WebUI cannot send a
code. Set them in the installer or configure `webui\config.json` `admin_email`
plus the SMTP secret, then restart `Cyber-Butler Web UI Services`.

This is separate from the AstrBot WebUI at `http://127.0.0.1:6185`, which uses
a username/password and does not require an email.

## 2. TOTP stays `pending`

- The owner QQ must be **different** from the bot QQ. An account cannot send a
  private message to itself and have AstrBot process it as an owner reply.
- Reply exactly:

  ```text
  <6-digit-code> SCOPED 30
  ```

- The challenge expires after 300 seconds; create a new request after expiry.
- Confirm the owner's incoming message appears in the AstrBot log and is not
  blocked by Security Gate.

## 3. `Bot not found or not running for platform: qq_sujinyan`

The UMO platform prefix is wrong. AstrBot's configured platform id is the
`id` field under `platform` in `AstrBot/data/cmd_config.json` (commonly `QQ`).
The Broker and the TOTP/security plugins must use the same value:

```text
<platform-id>:FriendMessage:<owner-qq>
```

If the configured id is `QQ`, use:

```text
QQ:FriendMessage:2351671738
```

Do not hardcode `qq_sujinyan` unless that is the actual platform id.

The v1.6.1 installer replaces `YOUR_QQ_ID`; if you upgraded from an older
package and still see `YOUR_QQ_ID`, replace it in:

```text
tools\broker.py
AstrBot/data/plugins/astrbot_plugin_totp_broker/main.py
AstrBot/data/plugins/astrbot_plugin_security_gate/main.py
AstrBot/data/plugins/astrbot_plugin_cloud_fallback/main.py
```

Then restart AstrBot and the Broker.

## 4. Security Gate blocks the owner

If the log says:

```text
[安全告警] 未知平台/umo，默认拦截
```

the `Security Gate` known markers are stale. The check runs on
`umo.casefold()`, so markers must be lowercase:

```python
known_markers = ("qq", "aiocqhttp", "qq_sujinyan")
```

The second inline marker check must use the same lowercase tuple. Delete the
plugin `__pycache__`, restart AstrBot, and send a normal `hello test` from the
owner before retrying TOTP.

## 5. AstrBot has multiple `main.py` or port 6185 is occupied

1. Stop `AstrBot Service`.
2. Stop every AstrBot `main.py` process:

   ```powershell
   Get-CimInstance Win32_Process |
     Where-Object {
       $_.CommandLine -match 'main\.py' -and
       $_.CommandLine -match 'AstrBot'
     } |
     ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
   ```

3. Ensure 6185 is no longer listening, start the task once, and check:

   ```powershell
   Get-NetTCPConnection -LocalPort 6185 -State Listen |
     Select-Object LocalPort,OwningProcess
   ```

Only one listener is acceptable. A launcher parent plus its Python worker is
normal; two independent `Running on ... 6185` blocks are not.

## 6. `tools` log is missing

`C:\CyberButler\tools` is read-only for the desktop account. Do not grant write
access. SnowLuma logs belong in:

```text
C:\CyberButler\SnowLuma\logs\start-snowluma.log
C:\CyberButler\SnowLuma\logs\startup-snowluma.out.log
```

The packaged script uses those paths.

## 7. `SnowLuma Startup` exists but nothing happens

Check:

```powershell
Get-ScheduledTaskInfo -TaskName 'SnowLuma Startup' |
  Format-List LastRunTime,LastTaskResult,NumberOfMissedRuns
```

`LastTaskResult=0` and a new timestamp mean the task ran. If the log has no new
entry, the task principal or working directory is wrong. The task must run as
the interactive desktop user, not SYSTEM.

## 8. `Auto-load` is on but injection still does not happen

- QQ must be logged in before SnowLuma can inject.
- `SNOWLUMA_HOOK_AUTOLOAD=true` must be set in the environment of the process
  that actually launches SnowLuma, not only in a different PowerShell window.
- Start SnowLuma from the `SnowLuma Startup` task after reboot.
- Check `startup-snowluma.out.log` for `hook auto-load enabled`.

## 9. `/api/v1/im/bots` returns `["QQ"]` but sending fails

`/im/bots` reads the configured platform ids; it does **not** prove a live
connection. Check `6199 Established` and the SnowLuma `OneBot.WS-Client`
log instead.

## 10. Scoped Token risks

- Do not paste a live `scoped_token` into chat or logs.
- The token is memory-only; Broker restart invalidates it.
- It is limited to the approved canonical directory, shared/tmp roots, and
  `delete` / `overwrite` / `write_file`.
- It never applies to memory/config, the TOTP vault, `send`, or a sibling
  directory.
- If a token appears in a terminal transcript, restart the Broker.

## 11. External limits

CBS cannot bypass:

```text
QQ national-network identity verification
QQ password/QR login
AstrBot model-provider configuration
Windows Task Scheduler interactivity requirements
antivirus/SmartScreen reputation
```

See [STATUS_v1.6.1.md](STATUS_v1.6.1.md) for the authoritative shipped,
incomplete, and non-guaranteed list.


---

# 12. Installer: CWD 错位导致密码 Hash / 种子写入失败

## 症状

```text
AstrBot WebUI 显示初始密码，但登录始终失败
seed_astrbot_dashboard.py 报 ModuleNotFoundError: astrbot
data/.cbs-dashboard-password-configured 不存在
```

## 根因

安装器以 `C:\CyberButler` 或临时目录为 CWD 启动 Python 脚本，而脚本依赖
AstrBot 包相对路径。Python 从错误的工作目录解析 import 和
`data/cmd_config.json`，于是 hash 写入了错误位置，或根本没有写入。

## 修复

1. 不依赖调用者的 CWD：

   ```powershell
   Push-Location 'C:\CyberButler\AstrBot'
   try {
     & '.venv\Scripts\python.exe' `
       'C:\CyberButler\tools\seed_astrbot_dashboard.py'
   } finally {
     Pop-Location
   }
   ```

2. 生成密码时只使用**绝对路径**，并在完成后验证：

   ```powershell
   Test-Path 'C:\CyberButler\AstrBot\data\.cbs-dashboard-password-configured'
   ```

3. 独立 hash 脚本不要 `import astrbot`，只使用标准库
   `hashlib.pbkdf2_hmac`，避免安装器 CWD 影响。

4. 安装器只有在 marker 存在时才显示“初始密码”；否则显示
   `data/logs/initial-admin-password.txt` 的路径，不要显示一个未生效的密码。

## 8 语言提示

```text
zh: 工作目录错位会导致密码 Hash 写入错误位置。
en: A wrong working directory writes the password hash to the wrong place.
de: Ein falsches Arbeitsverzeichnis schreibt den Passwort-Hash falsch.
es: Un directorio de trabajo incorrecto guarda el hash en el lugar equivocado.
fr: Un mauvais répertoire de travail écrit le hash au mauvais endroit.
ja: 作業ディレクトリが違うとパスワードハッシュが誤った場所に書き込まれます。
ko: 작업 디렉터리가 틀리면 암호 해시가 잘못된 위치에 기록됩니다.
ru: Неверный рабочий каталог записывает хэш пароля не туда.
```

# 13. High: S4U 被拒绝与密码回退

## 症状

```text
Register-ScheduledTask : Access is denied
AstrBot Service: LastTaskResult=0x00000002
```

## 根因

`S4U`（Service-for-User）不是所有 Windows 版本、域策略或本地安全策略都允许。
任务以 `CyberButlerSvc` 注册时，`LogonType=S4U` 可能在注册阶段直接被拒绝。

## 修复原则

1. **先测**：用目标服务账户注册一个最小任务。
2. **失败回退**：使用该账户的显式密码注册 `Password` 登录类型。
3. **不要回退为空密码**：`PSCredential` 的 SecureString 与任务需要的明文密码
   必须分开传递；回退时检查字符串非空。
4. 安装器必须记录回退原因，不要静默吞掉 S4U 错误。
5. 服务账户仍是标准用户；密码只进入 Windows 任务凭据，不写入项目文件。

## 验收

```powershell
Get-ScheduledTask -TaskName 'AstrBot Service' |
  Select-Object TaskName,State

Get-ScheduledTaskInfo -TaskName 'AstrBot Service' |
  Format-List LastRunTime,LastTaskResult
```

`LastTaskResult=0` 且端口 6185 在监听才算成功。

# 14. 0x00000002 与 0x00000001 的区别

## `0x00000002`

```text
任务已启动，但子进程/启动器在建立日志或端口之前就退出
```

常见原因：

- launcher 参数错误；
- PowerShell wrapper 相对路径错；
- 工作目录不可读；
- 子进程没有启动，日志文件不存在。

排查顺序：

```powershell
Get-ScheduledTaskInfo -TaskName 'AstrBot Service' |
  Format-List LastRunTime,LastTaskResult

Get-Content 'C:\CyberButler\AstrBot\data\logs\service-astrbot.err.log' -Tail 80 -ErrorAction SilentlyContinue
Get-Content 'C:\CyberButler\AstrBot\data\logs\service-astrbot.out.log' -Tail 80 -ErrorAction SilentlyContinue
```

## `0x00000001`

```text
Python 已经启动，但进程自身以 1 退出
```

常见原因：

- 使用 `pythonw.exe` 运行需要 stdout/stderr 的 AstrBot；
- AstrBot `main.py` 导入失败；
- 配置 JSON 损坏；
- 工作目录不是 `AstrBot`。

## 最容易踩的坑

把 AstrBot 强行改成 `pythonw.exe`，stdout 为 `None`，AstrBot 启动日志写入时
直接退出 1。正确方案：

```text
AstrBot: python.exe + hidden launcher + redirected stdout/stderr
WebUI / OTP Mailer: pythonw.exe
```

不要用“所有 Python 都改 pythonw”这种一刀切方案。

# 15. WebUI / SnowLuma 初始密码与“访问令牌”

## AstrBot

初始密码可能在：

```text
C:\CyberButler\AstrBot\data\logs\initial-admin-password.txt
```

但只有在安装器成功写入 `data\.cbs-dashboard-password-configured` 后，这个
密码才可信。否则用：

```powershell
Push-Location 'C:\CyberButler\AstrBot'
try {
  & '.venv\Scripts\python.exe' -m astrbot.cli password
} finally {
  Pop-Location
}
```

## SnowLuma WebUI

首次启动的随机密码由 SnowLuma 打印到 stdout：

```text
initial credentials: user=admin password=...
```

日志位置：

```text
C:\CyberButler\SnowLuma\logs\startup-snowluma.out.log
```

`SnowLuma\config\webui.json` 只保存 `passwordHash` / `passwordSalt`，不能从
hash 反推明文。密码丢失时要按 SnowLuma 的版本支持的恢复/重置方式处理，
不要删除配置文件后假装仍能登录。

## 三种 Token 不要混淆

```text
SnowLuma WebUI 登录密码
SnowLuma OneBot HTTP/WS 服务端 Token
SnowLuma 反向 WS 客户端 Access Token
AstrBot ws_reverse_token
AstrBot Open API Key（.astrbot_token）
Broker X-Broker-Token
```

只有：

```text
AstrBot platform[0].ws_reverse_token
=
SnowLuma networks.wsClients[].accessToken
```

是同一个共享 Token。

# 16. 黑框闪烁：一次把子进程全查完

## 典型触发

登录 CBS WebUI 后，前端轮询：

```text
/api/temps           每 5 秒 -> nvidia-smi
/api/config/email-status 每 10 秒 -> powershell.exe
```

Windows 上 `subprocess` 默认会为新控制台程序创建窗口。

## 必须做的修复

### Python 子进程

```python
import subprocess

_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)

subprocess.run(
    [...],
    capture_output=True,
    text=True,
    creationflags=_NO_WINDOW,
)
```

`check_output` 同样要加 `creationflags=_NO_WINDOW`。

### WebUI / OTP Mailer

使用：

```text
webui\.venv\Scripts\pythonw.exe
```

不要把 AstrBot 也改成 `pythonw.exe`；它需要 stdout。

### 计划任务 / 启动器

```text
CyberButlerLauncher.exe --hidden
  -> powershell.exe -WindowStyle Hidden
    -> run-python-hidden.ps1
      -> python.exe -WindowStyle Hidden
```

`New-ScheduledTaskSettingsSet -Hidden` 只能作为补充，不能替代
`CREATE_NO_WINDOW` / `pythonw` / `--hidden`。

## 排查

任务管理器观察一闪而过的：

```text
nvidia-smi.exe
powershell.exe
python.exe
pythonw.exe
cmd.exe
```

再用：

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -match 'CyberButler|nvidia-smi|email_secret_bridge' } |
  Select-Object ProcessId,Name,CommandLine
```

# 17. 卸载：强杀进程、解压包自噬、CBS profile

## 删除前

卸载器会停止：

```text
AstrBot Service
AstrBot TOTP Broker
Cyber-Butler Web UI Services
Cyber-Butler OTP Mailer
SnowLuma Startup
```

并对安装目录执行：

```text
taskkill /T /F
```

只杀安装目录下的进程树，不要直接杀整个 `python.exe` / `node.exe` 类别，
否则会误伤用户其他程序。

## 解压包“自噬”

`START-INSTALLER.exe` 正在运行时，Windows 不能删除它所在的目录。

旧实现只等 2 秒并尝试一次，所以解压目录永远残留。

修复方式：

```powershell
Start-Sleep -Seconds 8

for ($i = 0; $i -lt 30; $i++) {
  try {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $packageRoot)) { break }
  } catch { }
  Start-Sleep -Seconds 2
}
```

必须等 GUI 和 launcher 都退出后再删，不要在主进程内同步删除自己的目录。

## 不要删除 `C:\Users\CBS`

这是当前 Windows 用户 profile，里面有：

```text
Desktop
Downloads
AppData
浏览器/QQ/SnowLuma 用户缓存
```

删除它会破坏主账户，不是“清理残留”。

## 可以删除的桌面对象

```text
C:\Users\CBS\Desktop\大肥鱼专用文件夹
C:\Users\CBS\Desktop\Cyber-Butler 主控台.lnk
```

前者是用户文件，删除前必须让用户明确选择；后者只是快捷方式。

# 18. `C:\Users\CyberButlerSvc` 与 `UsrClass.dat` 锁死

## 症状

```text
Remove-CimInstance : 另一个程序正在使用此文件
UsrClass.dat
CyberButlerSvc profile 无法删除
```

## 根因

服务账户的 profile 仍被 Windows 加载。即使任务已停止，`UsrClass.dat` 仍可能
被系统保留到注销/重启。

## 安全清理顺序

1. 停止并确认五个任务已结束。
2. 只结束可执行文件路径位于
   `C:\Users\CyberButlerSvc` 内的进程。
3. `Remove-LocalUser -Name CyberButlerSvc`。
4. `Remove-CimInstance Win32_UserProfile` 重试 6 次。
5. 如果仍失败，写一次性 RunOnce：

```powershell
$runOnce = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
Set-ItemProperty -Path $runOnce -Name 'CyberButlerSvcProfileCleanup' `
  -Value 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Windows\Temp\CyberButler-svc-profile-cleanup.ps1"'
```

清理脚本在下次重启后删除 profile，然后删除自身。

6. **绝不**删除 `C:\Users\CBS`；RunOnce 只匹配 `CyberButlerSvc` 精确名称。

## 验收

```powershell
Get-LocalUser -Name 'CyberButlerSvc' -ErrorAction SilentlyContinue

Get-CimInstance Win32_UserProfile |
  Where-Object LocalPath -like '*\CyberButlerSvc' |
  Select-Object LocalPath,Loaded
```

卸载后应为空，或明确提示“下次重启清理”。

# 19. Broker 401 / `.astrbot_token` 缺失

## 症状

```text
Invoke-WebRequest : (401) 未经授权
QQ challenge send failed
Test-Path C:\CyberButler\.astrbot_token -> False
```

## 根因

Broker 调用 AstrBot Open API：

```text
POST http://127.0.0.1:6185/api/v1/im/messages
Authorization: Bearer <.astrbot_token>
```

缺少 API Key 时，AstrBot 返回 401，Broker 将其折叠为
`QQ challenge send failed`。

## 修复

在 AstrBot WebUI 创建 scope 为 `im` 的 API Key，写入：

```powershell
Set-Content -LiteralPath 'C:\CyberButler\.astrbot_token' `
  -Value $key.Trim() -Encoding ASCII -NoNewline

icacls 'C:\CyberButler\.astrbot_token' /inheritance:r
icacls 'C:\CyberButler\.astrbot_token' /grant:r `
  'SYSTEM:(F)' 'Administrators:(F)'
```

重启 Broker 后测试：

```powershell
$token = (Get-Content 'C:\CyberButler\.astrbot_token' -Raw).Trim()
```

这不是 `broker_token.txt`，也不是 TOTP。

# 20. `/request` 与 `/api/request_approval` 别混用

```text
/api/request_approval
  强制 approval_only=true
  只返回审批状态，不执行

/request
  可以 approval_only=false
  主人回复验证码后异步执行
```

如果你用 `/api/request_approval` 测试“真正执行”，文件永远是 `old`，
这是预期行为，不是 Broker bug。

# 21. scoped_token 不是全局状态

`SCOPED 30` 批准后，状态接口会返回：

```text
scoped_token
scoped_expires_in
scoped_root
```

下一次请求必须显式回传：

```json
{
  "scoped_token": "<the token>"
}
```

它不是保存到磁盘的全局开关，也不会因为同一个 PowerShell 窗口就自动携带。
换窗口后变量丢失，必须重新批准；Broker 重启也会清空。

# 22. 八语言索引 / Eight-language index

本指南的详细排障正文以英文和中文为主，因为命令、日志和 Windows 错误码是
通用的；README 的 8 种语言均包含测试覆盖声明和签名验证入口。

| 主题 / Topic | 中文 | English | Deutsch | Español | Français | 日本語 | 한국어 | Русский |
|---|---|---|---|---|---|---|---|---|
| Test coverage | 测试覆盖 | Test coverage | Testabdeckung | Cobertura | Couverture | テスト範囲 | 테스트 범위 | Покрытие |
| Installer CWD | 工作目录 | Working directory | Arbeitsverzeichnis | Directorio | Répertoire | 作業ディレクトリ | 작업 디렉터리 | Рабочий каталог |
| S4U | S4U 回退 | S4U fallback | S4U-Fallback | Respaldo S4U | Repli S4U | S4U フォールバック | S4U 대체 | Резерв S4U |
| Exit codes | 退出码 | Exit codes | Exitcodes | Códigos | Codes de sortie | 終了コード | 종료 코드 | Коды выхода |
| Initial password | 初始密码 | Initial password | Anfangspasswort | Contraseña inicial | Mot de passe initial | 初期パスワード | 초기 암호 | Начальный пароль |
| Black console | 黑框 | Console flash | Konsolenfenster | Ventana negra | Fenêtre noire | 黒い画面 | 검은 창 | Чёрное окно |
| Uninstall | 卸载 | Uninstall | Deinstallation | Desinstalación | Désinstallation | アンインストール | 제거 | Удаление |
| Profile lock | Profile 锁死 | Profile lock | Profil-Sperre | Bloqueo | Verrou | プロファイル固定 | 프로필 잠금 | Блокировка профиля |

# 致同路人的一封信 / A Letter to Fellow Travelers

如果你从本项目的源码、安装器、测试或这份排障记录里获得过帮助，欢迎把你遇到的
新坑、复现步骤、日志和修复方法分享回来。开源生态不是靠“我这里能跑”维持的，
而是靠失败记录、可复现的证据和愿意补上下一块缺口的人维持的。

If this project's source, installer, tests, or troubleshooting notes helped you,
please share the next failure you hit: reproduction steps, logs, and the fix.
An open-source ecosystem is sustained not by "it works on my machine", but by
failure records, reproducible evidence, and people willing to fill the next gap.

请不要只留下“我也遇到了”的帖子；请留下能让别人复现问题的命令、版本、Tier、
Windows 版本和最后一条日志。那才是下一个人真正需要的东西。

Do not leave only "me too". Leave the command, version, tier, Windows build, and
the last log line that lets the next person reproduce it. That is what the next
traveler actually needs.
