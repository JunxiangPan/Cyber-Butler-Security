# Cyber-Butler 安装说明 / Installation Guide

本文件在发布包根目录。先看本页，再启动安装。

This file is at the release root. Read it before launching the installer.

---

## 1. 从哪里开始 / Where to start

根目录双击：

```text
START-INSTALLER.cmd
```

它会启动 WPF 安装界面。不会打开管理员 PowerShell 控制台；UAC 提示是正常的。

也可以双击：

```text
installer\Start-CyberButler-Installer.vbs
```

Double-click `START-INSTALLER.cmd` at the release root. It opens the WPF installer. No administrator PowerShell console is shown; the UAC prompt is expected.

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

1. 双击根目录 `START-INSTALLER.cmd`。
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
- `C:\CyberButler\installer-report` 里的日志文件时间还在更新
- 安装器 PowerShell 进程仍存在，CPU 或内存有变化

### 已经失败

- GUI 弹出“安装失败”
- `C:\CyberButler\installer-report\install-report.json` 中 `status` 为 `failed`
- 安装器进程已经退出，但没有成功窗口
- 日志超过约 10 分钟完全没有变化

### 不要只看“界面不动”

Core 的 pip 安装可能持续数分钟，界面没有新行并不等于失败。以日志时间、进程和最终报告为准。

## 5. 报错时看哪里 / Where to look on failure

按顺序检查：

```text
C:\CyberButler\installer-report\install-report.json
C:\CyberButler\installer-report\install-report.md
C:\CyberButler\installer-report\pip-install.log
C:\CyberButler\installer-report\webui-pip-install.log
%TEMP%\CyberButler-Installer-GUI-error.log
C:\ProgramData\CyberButler\installer\state\
C:\ProgramData\CyberButler\installer\diagnostics\
```

常用检查命令：

```powershell
Get-Content "C:\CyberButler\installer-report\install-report.json" -Raw
Get-Content "$env:TEMP\CyberButler-Installer-GUI-error.log" -Tail 100 -ErrorAction SilentlyContinue
Get-ChildItem "C:\ProgramData\CyberButler\installer\diagnostics" -ErrorAction SilentlyContinue
```

`install-report.json` 很大时，PowerShell 5.1 的 `ConvertFrom-Json` 可能失败；用 Python 校验：

```powershell
& "C:\Users\PAN\AppData\Local\Programs\Python\Python313\python.exe" -c "import json; p=r'C:\CyberButler\installer-report\install-report.json'; d=json.load(open(p,encoding='utf-8')); print(d.get('status'))"
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
START-INSTALLER.cmd                 根目录快捷启动
README-INSTALL.md                   本说明
installer\                          安装器、GUI、TOTP、服务脚本
installer\Start-CyberButler-Installer.vbs
installer\CyberButler.Installer.GUI.ps1
VERSION                             版本号
docs/releases/RELEASE_NOTES_v1.6.1.md  发布说明（历史版本也在此目录）
AstrBot\ / webui\ / tools\           安装载荷
```

安装完成后，项目文件默认在：

```text
C:\CyberButler\
C:\CyberButler\installer-report\    安装报告
C:\ProgramData\CyberButler\         安装状态和诊断
```

发布包本身不会被安装器删除；不要把它和 `C:\CyberButler` 混在一起。

## 9. 卸载 / Uninstall

打开安装器 GUI，点击：

```text
删除程序 / Uninstall
```

确认后会：

- 停止并删除三个计划任务
- 停止项目端口上的进程
- 删除 Cyber-Butler 防火墙规则
- 删除安装目录
- 删除 `C:\ProgramData\CyberButler`
- 不删除发布包、下载的 zip 或源目录

## 10. 安全提醒 / Security

- TOTP secret 和 recovery codes 只离线保存。
- 不要把 API Key、SMTP 授权码、TOTP secret 发到聊天或仓库。
- 安装报告不写入 secret 值。
- 测试用的 TOTP 材料不要用于正式账号。
- 卸载不可恢复；确认前先备份需要保留的数据。
