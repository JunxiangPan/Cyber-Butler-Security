# Cyber-Butler v1.6.0

> Community acknowledgements: [CONTRIBUTORS.md](../../CONTRIBUTORS.md)

## 中文

### 一键部署

v1.6.0 引入统一的 `installer/Install-CyberButler.ps1`。安装器使用同一套执行管线，通过 `-Tier High|Medium|Light` 选择安全档位，不再维护三套割裂的安装脚本。

默认：

```text
Tier = Medium
EnableIsolation = false
WebUIBind = Loopback
```

安装流程：

```text
Preflight
  -> Plan + APPROVE PLAN
  -> Core Deploy
  -> Accounts -> ACL -> Firewall -> TOTP -> Secrets -> Services
  -> Diagnostics
  -> install-report.json / install-report.md
```

安全关键步骤必须输入对应确认词，例如 `APPROVE ACCOUNT`、`APPROVE ACL`、`APPROVE TOTP`、`APPROVE SERVICES`。`-NonInteractive` 缺少确认时退出码为 10，不会继续执行。

### 三档安全矩阵

| 能力 | High | Medium（默认） | Light |
|---|---|---|---|
| 双账户隔离 | 强制 | 默认关闭，可显式开启 | 默认关闭，可显式开启 |
| 代码 ACL | 服务账户只读 | 默认应用 | 仅保留最小 Broker 保护 |
| TOTP 删除/覆盖 | 强制 | 强制 | 强制 |
| TOTP 高危外发 | 开启 | 开启 | 裁剪 |
| Router fail-closed | 开启 | 开启 | 开启 |
| Web UI | Loopback + Tailscale Serve | Loopback | Loopback |
| LAN 直连 | 禁止 | 需显式批准 | 需显式批准 |
| API Key | DPAPI + ACL | DPAPI + ACL | DPAPI + ACL |
| 适用 | 高隔离需求 | 推荐默认 | 受控单机试玩 |

`Medium + Isolation` 与 `Light + Isolation` 会被如实标记，不会伪装成 High。

### 隔离迁移

新增 `installer/Migrate-EnableIsolation.ps1`：

```powershell
# 只输出迁移计划、差异、停机窗口预估和回滚方案
.\installer\Migrate-EnableIsolation.ps1 -PlanOnly

# 执行迁移，需要 APPROVE MIGRATE-ISOLATION
.\installer\Migrate-EnableIsolation.ps1 -Apply

# 只验证当前是否已完成隔离
.\installer\Migrate-EnableIsolation.ps1 -Verify

# 回滚最近一次迁移
.\installer\Migrate-EnableIsolation.ps1 -Rollback
```

迁移只涉及 AstrBot 与 Web UI 的账户/任务，**SnowLuma 和 TOTP Broker 不迁移**。数据不复制；失败时只恢复任务 XML、ACL 和 secret 引用。停机窗口估算为 2–5 分钟，必须在干净 VM 上实测。

### 已知限制

- 系统 Python 3.10-3.13 可直接使用；如果系统 Python 是 3.14+ 或不可用，安装器会自动下载 Python 3.13.17 到 `<InstallPath>\.python` 并用它创建 AstrBot venv，不再要求用户降级系统 Python。离线环境可通过 `-PythonPackage <官方 .exe>` 提供本地安装包。

- 本次 v1.6.0 已实现核心部署的下载、SHA-256 校验、解压、venv、依赖安装与 overlay 合并；真实下载源与完整安装路径尚未在干净 Windows 11 Pro VM 上完成集成验收。`installer/core-sources.json` 已固定 AstrBot v4.29.3 官方 tag 源码包与 SnowLuma v2.2.1 官方 win-x64 发布包的 URL/SHA-256；也可通过 `-AstrBotPackage` / `-SnowLumaPackage` 使用本地包。
- Block 3 的真实服务账户、ACL、防火墙执行路径需要 VM 验证：账户登录、AstrBot 启动、6185/18090/8765 可达性。
- TOTP/DPAPI/计划任务真实执行路径同样需要 VM 验证；当前自动化测试使用 handler 注入和 fake secret，不读取真实 DPAPI 密钥。
- `-Repair` 当前为只读诊断模式，不自动执行安全修复。
- CBS 开源包不含 `astrbot_plugin_private_companion`、`astrbot_plugin_livingmemory`、`astrbot_plugin_memorix` 三个个人定制插件；需要完整苏瑾言时，使用 `-PersonalPluginsPath` 指定这三个插件的源目录。
- 从 v1.5.x 迁移到 v1.6.0 时，v1.6.0 安装到独立目录（默认 `C:\CyberButler`），不是原地升级。需要用 `-PersonalPluginsPath` 指定旧安装的个人插件源（通常是 `D:\qq苏瑾言大肥鱼\AstrBot\data\plugins`），安装器会复制三个插件的代码文件。旧安装的 `AstrBot/data/`（记忆、对话历史、数据库）不自动迁移，需要手动处理。
- 从 v1.5.x 升级时，如果原来的插件已经在 v1.6.0 目标目录的 `AstrBot/data/plugins/` 里，可以不传 `-PersonalPluginsPath`，Core Deploy 会保留现有插件。
- overlay 现在包含 `provider.py`、`context.py` 等核心文件的大幅修改，已接近 fork。v1.6.1 会评估 fork AstrBot 定期 merge upstream 的路线，避免每次 AstrBot 升级都出现版本不匹配。
- 迁移实际耗时取决于数据目录大小、任务数量和 DPAPI 文件数量；文档中的 2–5 分钟只是预估值。

---

## English

### One-click deployment

v1.6.0 introduces a single `installer/Install-CyberButler.ps1`. It uses one
pipeline and selects the security tier with `-Tier High|Medium|Light` instead of
maintaining three separate installers.

Defaults:

```text
Tier = Medium
EnableIsolation = false
WebUIBind = Loopback
```

Pipeline:

```text
Preflight
  -> Plan + APPROVE PLAN
  -> Core Deploy
  -> Accounts -> ACL -> Firewall -> TOTP -> Secrets -> Services
  -> Diagnostics
  -> install-report.json / install-report.md
```

Security-critical steps require explicit approval tokens such as
`APPROVE ACCOUNT`, `APPROVE ACL`, `APPROVE TOTP`, and `APPROVE SERVICES`.
`-NonInteractive` exits with code 10 when an approval is missing and does not
continue.

### Three-tier security matrix

| Capability | High | Medium (default) | Light |
|---|---|---|---|
| Dual-account isolation | Required | Off by default; opt-in | Off by default; opt-in |
| Code ACL | Service account read-only | Applied by default | Minimal broker protection |
| TOTP delete/overwrite | Required | Required | Required |
| TOTP high-risk egress | Enabled | Enabled | Reduced |
| Router fail-closed | Enabled | Enabled | Enabled |
| Web UI | Loopback + Tailscale Serve | Loopback | Loopback |
| Direct LAN | Rejected | Explicit approval | Explicit approval |
| API key | DPAPI + ACL | DPAPI + ACL | DPAPI + ACL |
| Intended use | High-isolation deployments | Recommended default | Controlled single-machine use |

`Medium + Isolation` and `Light + Isolation` are labelled honestly and are not
presented as High.

### Isolation migration

`installer/Migrate-EnableIsolation.ps1` supports:

```powershell
.\installer\Migrate-EnableIsolation.ps1 -PlanOnly
.\installer\Migrate-EnableIsolation.ps1 -Apply
.\installer\Migrate-EnableIsolation.ps1 -Verify
.\installer\Migrate-EnableIsolation.ps1 -Rollback
```

The migration changes only AstrBot and Web UI identity/tasks. **SnowLuma and the
TOTP Broker are not migrated.** Data is never copied; rollback restores task
XML, ACLs, and secret references only. The 2–5 minute downtime estimate must be
measured on a clean VM.

### Known limitations

- System Python 3.10-3.13 is supported directly. When the system Python is 3.14+ or unavailable, the installer downloads Python 3.13.17 into `<InstallPath>\.python` and uses it to create the AstrBot venv; users no longer need to downgrade system Python. Offline installs can use `-PythonPackage <official .exe>`.

- v1.6.0 implements the core deployment download, SHA-256 verification,
  extraction, venv, dependency install, and overlay merge. The real download
  sources and the full install path have not yet been validated on a clean
  Windows 11 Pro VM. `installer/core-sources.json` pins the official AstrBot v4.29.3 tag source
  archive and SnowLuma v2.2.1 win-x64 release URL/SHA-256; local packages can
  be supplied with `-AstrBotPackage` / `-SnowLumaPackage`.
- The real service-account, ACL, and firewall paths still require VM validation:
  account logon, AstrBot startup, and 6185/18090/8765 reachability.
- TOTP/DPAPI/scheduled-task execution also requires VM validation. Automated
  tests use handler injection and fake secrets; they do not read real DPAPI keys.
- `-Repair` is currently read-only diagnostics; it does not execute security
  repairs.
- The migration duration depends on data size, task count, and DPAPI file count;
  the 2–5 minute figure is only an estimate.
