# Cyber-Butler 安装说明 / Installation Guide

## 0. 故障排查 / Troubleshooting

常见故障（SnowLuma 未自动注入、6199 未连接、QQ challenge send failed、TOTP 一直 pending、`YOUR_QQ_ID` 未替换、`qq_sujinyan` 平台前缀错误、6185 冲突）见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

Common failures and fixes: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).


本文件在发布包根目录。先看本页，再启动安装。

This file is at the release root. Read it before launching the installer.

---

## 1. 从哪里开始 / Where to start

根目录双击：

```text
START-INSTALLER.exe
```

它会启动 WPF 安装界面。不会打开管理员 PowerShell 控制台；UAC 提示是正常的。

旧的 VBS / `wscript.exe` 启动器已经移除。唯一入口是根目录的
`START-INSTALLER.exe`；它使用原生 C# 启动器，不再依赖 VBS 或 `.cmd`。

The old VBS / `wscript.exe` launcher is gone. The only entry point is
`START-INSTALLER.exe`, a native C# launcher that does not depend on VBS or
`.cmd`.

## 1.1 v1.6.1 安全能力 / v1.6.1 security capabilities

- **Scoped Token**：TOTP 审批时可回复 `SCOPED 30`，获得当前共享草稿目录
  30 分钟授权；仅限 `delete` / `overwrite` / `write_file`，不适用于
  memory/config、TOTP vault 或文件外发。
- **Job Object**：Broker 使用 `KILL_ON_JOB_CLOSE`，Broker 退出时终止其子进程树。
  AstrBot 是独立任务，不在该 Job 内。
- **DSH / Cordis**：单独的 `dsh-cbs-gate` bundle 使用 approval-only 接口；
  需要额外安装，不随 CBS 安装包自动进入 DSH profile。
- **Dashboard 完整性**：安装器会校验 dashboard 语法，并保护官方模块哈希，
  避免 `YOUR_QQ_ID` 占位符替换破坏模块。

## 1.2 v1.6.1 状态与不保证 / Status and non-guarantees

已完成、未完成、明确不保证的内容以
[docs/STATUS_v1.6.1.md](docs/STATUS_v1.6.1.md) 为准。安装成功不等于获得
绝对安全、第三方审计、代码签名或对未来 QQ/AstrBot/DSH 版本的兼容保证。

The authoritative shipped/incomplete/non-guaranteed list is
[docs/STATUS_v1.6.1.md](docs/STATUS_v1.6.1.md). A successful install is not a
guarantee of absolute security, third-party audit, code signing, or future
QQ/AstrBot/DSH compatibility.

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

## 1.4 WebUI 邮箱 / WebUI email

CBS WebUI（8765）使用预配置邮箱 + 邮件验证码，不提供注册。安装器的高级选项现在
提供 `WebUI 邮箱` 和 `SMTP 授权码`，默认使用 163 SMTP；两者留空时 WebUI 无法
发送验证码。AstrBot WebUI（6185）仍使用用户名/密码。

CBS WebUI (8765) uses a preconfigured email + OTP, not self-registration. The
installer now exposes `WebUI email` and `SMTP auth code` (163 SMTP defaults).
Leave them empty only if you do not need the CBS WebUI. AstrBot (6185) still
uses username/password.

安装完成窗口会显示 AstrBot 初始用户名和初始密码（从 `AstrBot\data\logs\service-astrbot.log` 捕获）。如果窗口没有显示密码，可在 AstrBot 目录运行 `.venv\Scripts\python.exe -m astrbot.cli password` 重置。

## 1.6 AstrBot 机器人完整配置 / Complete AstrBot bot setup

安装完成后，AstrBot 的完整配置步骤如下。8 种语言的同一份说明也会出现在安装完成窗口的“启动说明”中。

1. 打开 `http://127.0.0.1:6185/`，用安装完成窗口显示的用户名和密码登录。
2. 进入“快速引导”/“配置平台机器人”，添加平台。
3. 消息平台类型选择 **OneBot v11**（适配器通常显示为 `aiocqhttp`）。
4. 机器人名称填 `苏瑾言` 或自定义名称。
5. 反向 WebSocket 主机：`127.0.0.1`
6. 反向 WebSocket 端口：`6199`
7. 反向 WebSocket Token：从 `C:\CyberButler\AstrBot\data\cmd_config.json` 的 `platform[0].ws_reverse_token` 读取；必须与 `C:\CyberButler\SnowLuma\config\onebot_<机器人QQ>.json` 的 access token 一致。
8. 保存并启用，等待“适配器已连接”；SnowLuma `http://127.0.0.1:5099/` 应显示 QQ 在线，`6199` 应为 `Established`。
9. 配置文件位置：
   - `AstrBot\data\cmd_config.json`
   - `SnowLuma\config\onebot_<机器人QQ>.json`
   修改任一侧 token 后同步另一侧并重启对应服务。

After installation, complete the AstrBot platform setup:

1. Open `http://127.0.0.1:6185/` and log in with the username/password shown after installation.
2. Open Quick Start / Configure Platform Bot and add a platform.
3. Choose message platform **OneBot v11** (adapter usually `aiocqhttp`).
4. Bot name: `Su Jinyan` or your own.
5. Reverse WebSocket host: `127.0.0.1`
6. Reverse WebSocket port: `6199`
7. Reverse WebSocket token: read `platform[0].ws_reverse_token` from `C:\CyberButler\AstrBot\data\cmd_config.json`; it must match the access token in `C:\CyberButler\SnowLuma\config\onebot_<BOT_QQ>.json`.
8. Save and enable; wait for “adapter connected”. SnowLuma `http://127.0.0.1:5099/` should show QQ online and `6199` should be `Established`.
9. Config files: `AstrBot\data\cmd_config.json` and `SnowLuma\config\onebot_<BOT_QQ>.json`. If you change a token, sync the other side and restart the service.

## 1.7 大肥鱼文件与 SnowLuma / My Big Fish folder and SnowLuma

安装器会创建并使用与当前桌面账户对应的实际目录：

```text
<用户桌面>\大肥鱼专用文件夹
```

并把 `webui\config.json` 的 `file_root` 指向它。WebUI 左侧“我的大肥鱼文件”应直接显示这个目录；如果旧版本为空，可重新安装或把 `file_root` 改成该实际路径。

SnowLuma WebUI：`http://127.0.0.1:5099/`，用户名通常 `admin`；首次启动随机密码显示在 SnowLuma 控制台/日志（`SnowLuma\logs`）。SnowLuma 的 OneBot/网络 -> WebSocket 客户端需要填写：

```text
URL: ws://127.0.0.1:6199/ws
Access Token: 安装完成窗口显示的同一个 Reverse WebSocket Token
角色: Universal
```

不要混淆 SnowLuma WebUI 密码、OneBot HTTP/WS 服务端 Token、反向 WS 客户端 Token。与 AstrBot 对接只需要“反向 WS 客户端”的 Access Token 与 AstrBot 的 `ws_reverse_token` 一致。

The installer creates the actual per-user folder:

```text
<Desktop>\大肥鱼专用文件夹
```

and points `webui\config.json` `file_root` to it. SnowLuma WebUI is `http://127.0.0.1:5099/`, username usually `admin`; the first-start random password appears in the SnowLuma console/log. In SnowLuma -> OneBot/Network -> WebSocket client, use `ws://127.0.0.1:6199/ws`, the same token shown at installation completion, role `Universal`. Do not confuse the WebUI password, OneBot server tokens, and reverse-WS client token.

## 2. 安装前准备 / Before installing

- Windows 10/11 x64
- 管理员账户
- PowerShell 5.1
- 至少 2 GB 可用磁盘；安装 AstrBot 依赖和模型需要更多空间
- 不需要预先安装 Python：安装器会使用系统 Python 3.10–3.13，或提示使用捆绑 Python
- 准备一个用于审批/通知的主人 QQ（你自己的主账号，不是机器人 QQ）
- 准备机器人 QQ 的适配器配置（在安装后的 AstrBot 中配置）
- 可选：DeepSeek API Key
- 可选：三个个人插件的源目录

## 3. 安装步骤 / Installation steps

1. 双击根目录 `START-INSTALLER.exe`。
2. 确认 UAC。
3. 在 GUI 中选择安装路径、Tier、主人 QQ、WebUI 绑定。
4. 阅读界面说明，勾选批准。
5. 点击“开始安装”。
6. 等待进度条、当前步骤和日志。Core/pip 阶段可能需要几分钟。安装期间可点击“检查状态”查看进程、阶段、最后输出、报告和端口。
7. TOTP 对话框出现后：
   - 用手机扫描二维码
   - 离线保存 recovery codes
   - 勾选两项确认
8. 等待 Services 阶段完成。
9. 成功后会弹出“安装完成”窗口，可直接打开 WebUI、AstrBot、报告和本说明。

## 4. 如何判断“还在安装”还是“已经失败” / Running or failed

### 还在安装

满足任意一项即可认为仍在运行：

- GUI 进度条或当前步骤在变化
- GUI 日志还在增加
- `C:\ProgramData\CyberButler\installer-report` 里的日志文件时间还在更新
- 安装器 PowerShell 进程仍存在，CPU 或内存有变化

### 已经失败

- GUI 弹出“安装失败”
- `C:\ProgramData\CyberButler\installer-report\install-report.json` 中 `status` 为 `failed`
- 安装器进程已经退出，但没有成功窗口
- 日志超过约 10 分钟完全没有变化

### 不要只看“界面不动”

Core 的 pip 安装可能持续数分钟，界面没有新行并不等于失败。以日志时间、进程和最终报告为准。

## 5. 报错时看哪里 / Where to look on failure

按顺序检查：

```text
C:\ProgramData\CyberButler\installer-report\install-report.json
C:\ProgramData\CyberButler\installer-report\install-report.md
C:\ProgramData\CyberButler\installer-report\pip-install.log
C:\ProgramData\CyberButler\installer-report\webui-pip-install.log
%TEMP%\CyberButler-Installer-GUI-error.log
C:\ProgramData\CyberButler\installer\state\
C:\ProgramData\CyberButler\installer\diagnostics\
```

常用检查命令：

```powershell
Get-Content "C:\ProgramData\CyberButler\installer-report\install-report.json" -Raw
Get-Content "$env:TEMP\CyberButler-Installer-GUI-error.log" -Tail 100 -ErrorAction SilentlyContinue
Get-ChildItem "C:\ProgramData\CyberButler\installer\diagnostics" -ErrorAction SilentlyContinue
```

`install-report.json` 很大时，PowerShell 5.1 的 `ConvertFrom-Json` 可能失败；用 Python 校验：

```powershell
& "C:\Users\<YOUR_USERNAME>\AppData\Local\Programs\Python\Python313\python.exe" -c "import json; p=r'C:\ProgramData\CyberButler\installer-report\install-report.json'; d=json.load(open(p,encoding='utf-8')); print(d.get('status'))"
```

## 6. 如何检查服务 / Check services

```powershell
Get-ScheduledTask |
  Where-Object { $_.TaskName -match 'AstrBot Service|AstrBot TOTP Broker|Cyber-Butler Web UI' } |
  ForEach-Object {
    $i = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath
    [pscustomobject]@{ Task = $_.TaskName; State = $_.State; LastTaskResult = $i.LastTaskResult }
  } | Format-Table -AutoSize

Get-NetTCPConnection -State Listen -LocalPort 6185,18090,8765 -ErrorAction SilentlyContinue |
  Select LocalPort,OwningProcess,State
```

服务日志：

```text
C:\CyberButler\AstrBot\data\logs\
C:\CyberButler\webui\data\
```

## 7. 安装完成后 / After installation

### 打开界面

- Cyber-Butler WebUI：`http://127.0.0.1:8765/`
- AstrBot 管理界面：`http://127.0.0.1:6185/`
- Broker 健康检查：`http://127.0.0.1:18090/health`

### 下一流程

1. 打开 WebUI，确认页面能加载。
2. 在 AstrBot 中配置机器人 QQ / QQ 适配器；主人 QQ 只用于 owner 审批和通知，不是机器人账号。
3. 配置模型 provider：
   - 安装器里的 API Key 字段只写 DeepSeek；
   - 其他大模型或 OpenAI-compatible API 在 AstrBot provider 配置中添加。
4. 发一条测试消息，确认机器人和 TOTP/Broker 正常。
5. 把 TOTP recovery codes 离线保存，不要截图或发到聊天。
6. 需要局域网/Tailscale 访问时，再单独配置网络和防火墙；High 档位禁止 LAN。

## 8. 发布包里有什么 / What is in the package

```text
START-INSTALLER.exe                 根目录快捷启动
README-INSTALL.md                   本说明
installer\                          安装器、GUI、TOTP、服务脚本
START-INSTALLER.exe
installer\CyberButler.Installer.GUI.ps1
VERSION                             版本号
docs/releases/RELEASE_NOTES_v1.6.1.md  发布说明（历史版本也在此目录）
AstrBot\ / webui\ / tools\           安装载荷
```

安装完成后，项目文件默认在：

```text
C:\CyberButler\
C:\ProgramData\CyberButler\installer-report\    安装报告
C:\ProgramData\CyberButler\         安装状态和诊断
```

发布包本身不会被安装器删除；不要把它和 `C:\CyberButler` 混在一起。

## 9. 卸载 / Uninstall

打开安装器 GUI，点击：

```text
删除程序 / Uninstall
```

选择删除范围：

```text
只删除安装程序/发布包
只删除主项目 C:\CyberButler
同时删除发布包和主项目
```

然后进行二次确认。

主项目删除会：

- 停止并删除三个计划任务
- 停止项目端口上的进程
- 删除 Cyber-Butler 防火墙规则
- 删除安装目录
- 删除 `C:\ProgramData\CyberButler`

发布包删除会删除解压后的发布目录；如果同目录下存在与版本匹配的 `public-release-v*.zip`，也会一并删除。

卸载不可恢复；确认前先备份需要保留的数据。

## 10. 日志与二维码 / Logs and QR

- GUI 模式不再把 TOTP secret、恢复码或二维码路径写入安装器日志。
- 状态窗口也会过滤这些行。
- TOTP 确认成功后，安装器会删除 `C:\CyberButler	ools	otp-vault	otp_qr.png`。
- 旧版本留下的临时日志可能包含敏感内容，建议清理：

```powershell
Remove-Item "$env:TEMP\cb-gui-totp-*" -Recurse -Force -ErrorAction SilentlyContinue
```

如果旧日志或二维码已经外泄，必须重新生成 TOTP，不要继续使用旧的 recovery codes。

## 11. 安全提醒 / Security

- TOTP secret 和 recovery codes 只离线保存。
- 不要把 API Key、SMTP 授权码、TOTP secret 发到聊天或仓库。
- 安装报告不写入 secret 值。
- 测试用的 TOTP 材料不要用于正式账号。
- 卸载不可恢复；确认前先备份需要保留的数据。

📚 [ROADMAP](ROADMAP.md) · [CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) · [TROUBLESHOOTING](docs/TROUBLESHOOTING.md)
