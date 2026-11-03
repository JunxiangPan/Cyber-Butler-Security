# v1.6.1 — 2026-11-02 Addendum

> This addendum supersedes older launcher, WSH, and test-count claims later in
> this file. The authoritative shipped/incomplete/non-guaranteed list is
> [docs/STATUS_v1.6.1.md](../STATUS_v1.6.1.md).

## ✅ 测试覆盖声明 / Test Coverage

✅ **High 档**：已完成完整的实机端到端测试（安装、服务拉起、TOTP、SCOPED、卸载）。

⚠️ **Medium 档**：已完成多次局部测试，大概率可用，但未做全流程完整验收。

❌ **Light（最小）档**：尚未进行完整的实机测试，请用户自行评估风险。

✅ **High tier**: full real-machine end-to-end test completed — install, service startup, TOTP, SCOPED, and uninstall.

⚠️ **Medium tier**: multiple partial tests completed; very likely usable, but the complete end-to-end flow has not been accepted on a real machine.

❌ **Light (minimal) tier**: no complete real-machine test has been performed yet; assess the risk yourself before using it.

This declaration applies to the v1.6.1 release and is not a security certification.

## Completed after the first v1.6.1 draft

### Security runtime

- **Scoped Token (30 minutes)**: TOTP approval can grant `SCOPED 30` for the
  current shared scratch/tmp directory. The token is memory-only, bound to the
  canonical directory, limited to `delete` / `overwrite` / `write_file`, and
  never valid for memory/config, the TOTP vault, `send`, or sibling directories.
- **approval-only API**: `/api/request_approval` and
  `/api/request_approval/status`; approved state can return the scoped token to
  the authenticated DSH caller. Broker does not execute in approval-only mode.
- **Job Object**: `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` is set before children
  start; Broker descendants are killed when the Broker's last job handle closes.
- **UIPI hook**: `UIPI_BLOCKED_GUI_INTERACTION` audit event and
  `guard_gui_result()` defensive wrapper.
- **Native launcher**: `START-INSTALLER.exe` replaces the old `.vbs` /
  `wscript.exe` / `.cmd` chain. No VBS launch path remains.
- **Dashboard integrity**: installer syntax check plus official dashboard-module
  hash protection.

### DSH / Cordis

`dsh-cbs-gate` is a separate bundle, not part of the CBS installer. It uses
`tools/pre-execute`, approval-only requests, status polling, and a per-instance
scoped-token cache. `edit` and shell tools remain refused.

### Verification

- `pytest: 95 passed`
- `Pester: 144 passed`
- Windows Job Object child test: child `sleep(60)` -> `CHILD_GONE` after parent exit.

## Still incomplete

AstrBot child processes are not yet in the Broker Job; there is no AppContainer
or syscall sandbox; shell/edit mediation and media TOTP are not complete. The
release manifest is signed, but there is no third-party audit. High-tier
real-machine acceptance is complete; Medium is partially tested and Light has no
complete real-machine test. See the status page.

## Not guaranteed

CBS does not guarantee absolute security, non-bypassability, coverage of every
tool/plugin/shell/Python/GUI/egress path, antivirus acceptance, or protection
against a compromised phone/QQ/desktop/admin account. It is defense-in-depth,
not a complete security product.

---

# Complete v1.6.1 Feature Inventory

This section is the release engineering checklist for v1.6.1. The authoritative
shipped/incomplete/non-guaranteed list is
[docs/STATUS_v1.6.1.md](../STATUS_v1.6.1.md).

## 1. Installer and deployment experience

- **WPF visual installer** for High / Medium / Light: install path, owner QQ,
  WebUI bind, optional API-key file, optional personal plugins.
- **Eight-language UI**: main window, dialogs, status panel, uninstall prompts,
  and help use zh/en/de/es/fr/ja/ko/ru. New Defender strings are zh/en with
  English fallback for the other six locales.
- **No-console native launch**: `START-INSTALLER.exe` is native C#; no
  `wscript.exe`, `.vbs`, or `.cmd` chain. Services use `pythonw.exe` or the
  native launcher.
- **Progress and diagnostics**: monotonic progress, elapsed/current/total ETA,
  PID/CPU/working set, copyable status window refreshed during installation.
- **Persistent failure report**: failed installs write
  `C:\ProgramData\CyberButler\installer-report\install-report.json` before
  rollback, so the report survives cleanup.
- **Defender allowlist guidance**: opt-in, default off, exact
  `C:\CyberButler` only, via `Add-MpPreference -ExclusionPath`; never disables
  real-time protection, SmartScreen, or broad drives.
- **Scoped uninstall**: package/project/both, stops processes, removes firewall
  rules and scheduled tasks, preserves reports.
- **High-tier account and launch fixes**: v1.6.1 used an S4U/password task
  fallback; that historical path is retired in v1.6.2 in favour of the SCM
  service `CyberButlerAstrBot`.

## 2. Broker and runtime controls

- **Job Object**: `KILL_ON_JOB_CLOSE` is set before child creation; Broker joins
  the job, descendants inherit it, and Windows kills the remaining tree when
  the Broker's last handle closes.
- **Approval-only**: `/api/request_approval` with `approval_only: true` changes
  approval state only; the Broker does not execute. DSH executes the original
  tool after `approved`.
- **Scoped Token (30 minutes)**: `<code> SCOPED 30` issues an in-memory token
  bound to the target directory, limited to `delete`/`overwrite`/`write_file`
  in SHARED or TMP_ROOTS. Never memory/config, vault, `send`, or siblings.
- **30-second bypass**: `<code> BYPASS 30` for repeated actions in the same
  action/directory context.
- **UIPI hook**: `UIPI_BLOCKED_GUI_INTERACTION` and `guard_gui_result()` for a
  future AppContainer/restricted-token GUI path. No real GUI bridge exists yet.
- **Audit**: JSONL records scoped use, `Scoped via 30-minute Directory Token`,
  and `auto_executed: false`; raw tokens/TOTP are never logged.

## 3. Ecosystem and plugin integration

- **DSH/Cordis `dsh-cbs-gate`**: `tools/pre-execute`; read tools pass;
  `write` -> `write_file`; `delete_file` -> `delete`;
  `edit`/`execute_shell`/`ops_bash`/`pwsh` are refused.
- **SafeToolExecutor**: broker-token header, approval-only request, one-second
  status polling, fail-closed, scoped-token cache, clear on `scoped_invalid`.
- **AstrBot native plugin**: parses `SCOPED 30` and `BYPASS 30`.
- **WebUI hardening**: Loopback default; non-loopback choices are checked
  against firewall/network-profile expectations and are warned or rejected by
  tier.

## 4. Release engineering and network boundary

- **RSA-3072 signing capability**: pinned public key, `sign_release.py`, and
  `verify_release.py`; private key stays outside the repo under SYSTEM/Admin ACL.
- **AstrBot overlay pinned**: 4.29.3 plus official-file hashes and explicit
  local-only entries; fork drift is rejected.
- **Personal plugin decoupling**: no default bundling; `-PersonalPluginsPath`
  explicitly copies the three optional plugins.

## 5. Tests

- **Pester: 144 passed / 0 failed** (ACL, service registration, environment).
- **Pytest: 95 passed** (TOTP/replay, scoped binding/expiry, approval-only HTTP,
  audit, Job Object hooks, UIPI).
- **Windows Job Object child test**: child `sleep(60)` -> `CHILD_GONE` after
  parent exit.

## v1.6.0 -> v1.6.1 delta (deep check)

| Area | v1.6.0 package | v1.6.1 package |
|---|---|---|
| Installer | unified PowerShell CLI, no WPF GUI, no `README-INSTALL.md` | WPF GUI, tier/path/API-key/owner, ETA/status, persistent report |
| Launch chain | 5 `.vbs` files under `tools/` (wscript/WSH) | 0 VBS, 0 CMD; native `START-INSTALLER.exe` / `CyberButlerLauncher.exe` |
| Broker | 33,596-byte execute-on-approval Broker | 66,233-byte Broker with Job, approval-only, status, scoped, bypass, UIPI |
| DSH | no bridge | separate `dsh-cbs-gate` with pre-execute/poll/cache |
| Dashboard | no install-time syntax gate / module-hash protection | syntax validation and official-module hash preservation |
| ACL | High/Medium/Light split | knowledge_base/site-packages handling, plugins read-only, exact runtime paths |
| Package | previous release | the final file/entry counts published with the release assets |
| Tests | lower baseline | 144 Pester + 95 pytest |
| Docs | English/Chinese-centric, no v1.6.1 status | eight languages, status page, full release inventory |

**Current signing status:** the code still supports the existing RSA-3072
release flow. The v1.6.1 `update-manifest.json` is signed for this release;
verify `update-manifest.sig` with `tools/update_pubkey.pem`. If the signature is
absent or invalid, treat the package as unsigned and do not publish it.

---

# v1.6.1 - Installer Reliability and Visual Setup

v1.6.1 focuses on the clean-install path: the Web UI launcher now resolves the production layout, creates its mailer token when missing, and keeps the Web UI available when the optional OTP mailer cannot start. It also adds a WPF front-end and the updater metadata fix needed by production merges.

⚠️ Note: A v1.5.3 installation must use the full installer to cross the release-key and overlay-format change. The legacy updater and the v1.6.0 merge path are not a supported bootstrap route.

🔧 Installer Reliability

**Web UI root**: `start-services.ps1` now detects both the production `webui` layout and the `public-release` layout before resolving `webui-config.json`.

**Mailer token**: a missing `webui\data\mailer_token` is generated as 32 random bytes encoded as 64 hex characters; an existing token is preserved.

**Non-blocking OTP**: an OTP mailer failure is logged as a warning and no longer prevents the Web UI from starting or aborts the whole service assertion.

**Config fallback**: a `webui\config.json` layout is accepted when the root-level `webui-config.json` is absent.

🖥️ Visual Installer

**WPF front-end**: `installer\CyberButler.Installer.GUI.ps1` collects the install path, tier, owner QQ, WebUI bind, optional personal-plugins path, and optional API-key file. The UI has Chinese and English labels, an inline help panel, a progress bar with current-step text, completion/failure dialogs, and runs the installer as a hidden child process; preflight runs automatically on open, and TOTP enrollment is a WPF dialog with the QR image and recovery codes. A post-install window offers WebUI, AstrBot, the install guide and the report. A status button remains available during installation and reports the current stage, step completion, elapsed-based step ETA, overall ETA, process details, last output age, report status, service ports, tasks and recent log lines in a copyable window. The status window refreshes every three seconds and has an explicit Refresh button; the button is also present during installation. The completion state is forced to 100% when the report says success, and the timer resumes after TOTP confirmation so the post-install window appears. TOTP log messages now distinguish waiting for enrollment from continuing to services. A separate GUI completion watcher polls the report, so the post-install window appears even if the TOTP timer stops. The report now finalizes an existing in-progress security step when its module returns skipped/completed, and TOTP vault diagnostics use the actual TOTP reader account instead of the service account in single-account mode. GUI mode suppresses TOTP secret/recovery/QR output, filters sensitive lines in status, and deletes the QR image after enrollment. The GUI has a refined dark theme, collapsed advanced options, field tooltips, an Installing... disabled start button, a full-path tooltip, and a three-choice removal flow (package, project, or both) with a second confirmation. Closing the window with X during installation asks for confirmation and stops the installer process tree. The GUI language selector now covers every README language: zh, en, de, es, fr, ja, ko and ru, with all UI/status/remove/help strings translated. Tier and WebUI bind option labels are localized while internal values stay stable. The GUI passes the required EnableIsolation flag for High and AcceptLowerSecurity for Light. High account setup now adds the service account to the Users group explicitly, writes user-right SIDs with the secedit-required *S- prefix, uses the Windows LSA API (LsaAddAccountRights / LsaEnumerateAccountRights) for service-account logon rights instead of secedit, verifies each right, and includes the individual assertion fields when it still fails. v1.6.1 used an S4U/password fallback; this historical path is superseded by the v1.6.2 SCM service (CyberButlerAstrBot). v1.6.1 carried a task password separately for its fallback; v1.6.2 supersedes that path with the SCM service and does not register AstrBot as a scheduled task. High now copies a per-user system Python runtime into <InstallPath>\.python and creates the venv from that service-readable copy; the original per-user Python path is unreadable to CyberButlerSvc. AstrBot service stdout is redirected to AstrBot/data/logs/service-astrbot.log, which is writable, instead of the read-only data root. High isolation now uses a split data ACL: AstrBot/data itself and AstrBot/data/memory and data/config are read-only for the service account, while data/cache, data/tmp, data/temp, data/logs and data/plugin_data are writable; data/memory, data/config, data/knowledge_base and data/site-packages are created read-only; inherited Authenticated Users write ACEs are removed, and project data/workspace remain writable. The Broker now classifies requests server-side: tmp/cache paths auto-execute, memory/config paths require TOTP, and totp-vault paths are denied. It also supports write_file and send_file; the TOTP plugin exposes write and send tools. Failure reports are written under ProgramData so a rollback cannot delete them, and the GUI shows a failure dialog even when no report was produced. A sanitized eight-language startup and login guide is available from the post-install window, and a dashboard desktop shortcut is created after services start. The dashboard now launches through a wrapper that writes a diagnostic log and shows a visible error instead of failing silently. The preflight-complete status is re-rendered when the language changes, not frozen in the startup language. The launcher is the native `START-INSTALLER.exe`; no administrator PowerShell console is shown. The release root contains `START-INSTALLER.exe` and `README-INSTALL.md`.

**Preflight in the UI**: the GUI can run a read-only environment preflight and display its JSON result.

**Explicit approval**: the GUI requires an explicit approval checkbox before it supplies the approval tokens. It never auto-approves silently. While installation runs, every action except Exit is disabled; Exit asks for confirmation and stops the hidden installer. **Uninstall**: the GUI has a one-click Uninstall action that verifies Cyber-Butler markers, stops tasks/processes, removes its firewall rule, deletes the install root and ProgramData state, and never removes the source zip.

🛡️ Update Integrity

**Overlay metadata**: `update_merge_core.py` skips `overlay/overlay-manifest.json` as release metadata instead of treating it as an AstrBot runtime overlay target.

**Public key allowlist**: `tools/update_pubkey.pem` is accepted by the updater allowlist; other `.pem` files remain rejected.

**TOTP runtime paths**: the Broker now resolves `tools/totp-vault/totp_secret.dpapi` and `recovery_hashes.json`, with a legacy fallback to the old root paths.

**Broker ACL**: the installer hardens `tools` and `AstrBot/.venv` before TOTP enrollment. In single-account Medium mode it records the unavoidable TOTP-vault limitation in `single-account.marker`; High isolation still requires the explicit deny.

**WebUI data protection**: updater protection now covers `webui/data/mailer_token` and the TOTP vault files.

**Language**: the visual installer has Chinese/English UI labels.

**Version**: the repository version is now `1.6.1`.

✅ Verification

Host Pester: 144 passed, 0 failed.

GUI XAML self-test: `GUI_XAML_OK`.

Relevant pytest: 95 passed.

⚠️ Known Limitations

Clean Windows 11 Pro VM end-to-end acceptance has not yet been run for this draft.

The visual installer is a front-end and preflight tool, not a fully silent unattended installer. The first installation still requires a UAC-elevated GUI and explicit approval/TOTP interaction.

Progress is polled from the hidden installer output; there is no per-package ETA.

`update_merge.ps1` still needs a dedicated `webui\.venv` bootstrap/check for targets where that virtual environment is absent.

The v1.6.1 package is rebuilt for this release. If `update-manifest.sig` is absent from the release assets, the build is unsigned; do not claim otherwise.

AstrBot and Web UI remain Interactive scheduled tasks; logging off the desktop session can still terminate them. Use an auto-logon policy or a non-interactive service model for unattended deployment.

---

# v1.6.1 - 安装可靠性修复与可视化安装

v1.6.1 聚焦干净安装路径：Web UI 启动器现在能识别生产目录结构，在缺少 mailer token 时自动生成，并在可选 OTP mailer 启动失败时保持 Web UI 可用。本版本同时加入 WPF 前端，以及 production merge 所需的 updater metadata 修复。

⚠️ 注意：v1.5.3 安装必须使用完整安装器跨越发布密钥和 overlay 格式变更。旧更新器和 v1.6.0 的 merge 路径不是受支持的 bootstrap 路径。

🔧 安装可靠性

**Web UI root**：`start-services.ps1` 现在同时识别生产 `webui` 目录结构和 `public-release` 目录结构，再解析 `webui-config.json`。

**Mailer token**：`webui\data\mailer_token` 不存在时，生成 32 字节随机数并编码为 64 位 hex；已有 token 不覆盖。

**OTP 非阻塞**：OTP mailer 启动失败只写 warning，不再阻止 Web UI 启动，也不再让整个 Services 断言失败。

**配置回退**：根级 `webui-config.json` 不存在时，接受 `webui\config.json` 布局。

🖥️ 可视化安装器

**WPF 前端**：`installer\CyberButler.Installer.GUI.ps1` 收集安装路径、Tier、Owner QQ、WebUI 绑定、可选个人插件路径和可选 API key 文件。界面支持中文/英文，打开后自动执行环境检查，安装器作为隐藏子进程运行；TOTP 注册使用带 QR 和恢复码的 WPF 对话框。安装成功后弹出完成窗口，可浏览 WebUI、AstrBot、安装说明和报告。安装期间保留“检查状态”按钮，可查看当前阶段、步骤完成度、按已用时间计算的当前步骤预计剩余、总预计剩余、进程详情、最后输出时间、报告状态、服务端口、任务状态和最近日志；内容在可复制窗口中显示，每 3 秒自动刷新，并提供独立的“刷新”按钮；安装期间也可用。报告为 success 时状态强制显示 100%；TOTP 确认后计时器继续运行，完成窗口不会因 TOTP 弹窗而停住。TOTP 日志现在区分“等待扫码”和“已确认，继续服务”。GUI 另有独立完成监视器轮询报告，即使 TOTP 计时器停止也会弹出完成窗口。报告现在会把已存在的 in_progress 安全步骤正确收尾；单账户模式下 TOTP 保险箱诊断改用真实 TOTP 读取账户，而不是服务账户。GUI 模式不再输出 TOTP secret/恢复码/二维码路径，状态窗口过滤敏感行，TOTP 确认后删除二维码；界面改为更清晰的深色主题，高级选项默认折叠，关键字段有 Tooltip，开始安装后按钮变为“安装中...”并禁用，底部路径有完整 Tooltip；删除功能提供“发布包 / 主项目 / 两者”三种选择并二次确认。安装期间点 X 会二次确认，并在确认后终止安装器进程树。GUI 语言选择现已覆盖 README 的全部语言：中文、English、Deutsch、Español、Français、日本語、한국어、Русский；界面、状态窗口、删除窗口和帮助内容均已翻译，安全档位和 WebUI 绑定选项本地化但内部值保持稳定。GUI 会为 High 自动传 EnableIsolation，为 Light 自动传 AcceptLowerSecurity。High 账户初始化会显式加入 Users 组，按 secedit 要求写入带 *S- 前缀的用户权限 SID，服务账户登录权限改用 Windows LSA API（LsaAddAccountRights / LsaEnumerateAccountRights），不再依赖 secedit，并逐项验证；失败时记录各账户检查字段。v1.6.1 曾使用 S4U/密码回退；该历史路径已由 v1.6.2 的 SCM 服务（CyberButlerAstrBot）取代。v1.6.1 的任务密码回退仅作为历史路径；v1.6.2 已改为 SCM 服务，不再把 AstrBot 注册为计划任务。High 现在会把用户级系统 Python 复制到 <InstallPath>\.python，并用这份服务账户可读的副本创建 venv；原来的用户目录 Python 对 CyberButlerSvc 不可读。AstrBot 服务输出改写到可写的 AstrBot/data/logs/service-astrbot.log，而不是只读的 data 根目录。High 隔离现在使用拆分的 data ACL：AstrBot/data 本身、data/memory 和 data/config 对服务账户只读；data/cache、data/tmp、data/temp、data/logs、data/plugin_data 可写；data/memory、data/config、data/knowledge_base、data/site-packages 预先创建为只读；移除继承的 Authenticated Users 写 ACE；项目 data/workspace 保持可写。Broker 增加服务端路径分级：tmp/cache 直接执行，memory/config 走 TOTP，totp-vault 直接拒绝。Broker 新增 write_file 和 send_file，TOTP 插件暴露写入/发送工具。TOTP 保险箱会直接给 secret 和 recovery hash 文件写入 Deny ACE（Windows 不保证新继承 Deny 自动传播到已有文件），TOTP 验证也会检查这些文件。Broker ACL 验证接受 icacls 显示为 (N)/(F) 的 Deny。High/Medium 下 AstrBot 均通过原生 `CyberButlerLauncher.exe` 启动，不再经过 wscript 或 cmd.exe。服务就绪等待从 60 秒提高到 180 秒（旧的 60 秒断言可能在 AstrBot 插件加载完成前就超时）。AstrBot 通过原生启动器把 stdout/stderr 重定向到 AstrBot/data/logs/service-astrbot.log，服务账户启动失败可直接诊断。失败报告写入 ProgramData，回滚不会删除；即使没有生成报告，GUI 也会显示失败对话框。安装完成窗口提供已脱敏的八语言启动与登录说明；服务启动后创建主控台桌面快捷方式。主控台改为通过带诊断日志的包装器启动，失败时会显示错误而不是静默无响应。环境检查完成状态会随语言切换重新渲染，不再停留在启动时语言。启动器改为原生 `START-INSTALLER.exe`，不再显示管理员 PowerShell 控制台。发布包根目录包含 `START-INSTALLER.exe` 和 `README-INSTALL.md`。

**界面内预检**：GUI 可以运行只读环境预检并显示 JSON 结果。

**显式批准**：GUI 只有在用户勾选批准后才提供 approval token，不会静默自动批准安全步骤。安装期间除“退出”外所有按钮和输入框禁用；退出会确认并停止隐藏安装器。**一键删除**：GUI 提供删除按钮，校验 Cyber-Butler 标记后停止任务/进程、删除防火墙规则、安装目录和 ProgramData 状态，不删除源 zip。

🛡️ 更新完整性

**Overlay metadata**：`update_merge_core.py` 将 `overlay/overlay-manifest.json` 作为发布元数据跳过，不再把它当作 AstrBot 运行时 overlay 目标。

**公钥放行**：更新器 allowlist 接受 `tools/update_pubkey.pem`；其他 `.pem` 继续拒绝。

**TOTP 运行路径**：Broker 现在解析 `tools/totp-vault/totp_secret.dpapi` 和 `recovery_hashes.json`，并兼容旧的根路径。

**Broker ACL**：安装器在 TOTP 注册前硬化 `tools` 和 `AstrBot/.venv`。单账户 Medium 模式会在 `single-account.marker` 中记录无法强制 TOTP vault Deny 的限制；High 隔离仍要求显式 Deny。AstrBot 和 WebUI 通过原生 `CyberButlerLauncher.exe` 无控制台启动；Broker 使用 pythonw.exe。桌面不会残留控制台窗口。

**WebUI 数据保护**：更新器保护范围增加 `webui/data/mailer_token` 和 TOTP vault 文件。

**语言**：可视化安装器支持中文/英文界面标签。

**版本**：仓库版本更新为 `1.6.1`。

✅ 验证

主机 Pester：144 passed，0 failed。

GUI XAML 自检：`GUI_XAML_OK`。

相关 pytest：95 passed。

⚠️ 已知限制

本草案尚未在干净 Windows 11 Pro VM 上完成端到端验收。

可视化安装器是前端和预检工具，不是完全静默的无人值守安装器；首次安装仍需要提权 GUI 和显式批准/TOTP 操作。

进度来自隐藏安装器输出轮询，不提供精确剩余时间。

`update_merge.ps1` 仍需要补上 `webui\.venv` 的专用创建/检查逻辑，以覆盖虚拟环境缺失的目标机。

本版本的发布包已重新构建；仍未签名，最终签名必须在管理员上下文中完成。

AstrBot 和 Web UI 仍是 Interactive 计划任务；注销桌面会话仍可能终止它们。无人值守部署需要自动登录策略或非交互服务模式。


## Community Credits (from r/AI_Agents)

This project is shaped by the community. Special thanks to u/Auten,
u/Reid Marlow, u/QuanTradin, u/Practical-Craft4967, u/More-Ad7285, and
u/HeartMaleficent35 from r/AI_Agents for their architectural feedback and
security audits.

### u/Auten (Auten Team — screen-control Agent team)

Known pain points/advice:

- Session 0 isolation is useful, but AppContainer/downranked GUI interaction
  can fail silently through UIPI; the user may think the plugin is broken.
- The industrial architecture for GUI interaction is a background service plus
  a lightweight user-session Helper over a Named Pipe.

Status: v1.6.1 adds the `UIPI_BLOCKED_GUI_INTERACTION` audit hook. The
Named Pipe + Helper architecture is on the v1.7 roadmap, not shipped in 1.6.1.

### u/Reid Marlow

Known pain points/advice:

- An agent may tamper with `tests/` to pass checks; the test environment must
  be reset.
- A config change that syncs to production cannot always be recovered with
  `git revert`.
- Diff-boundary/staging interception must block writes outside an allowlist
  before they happen, even when CI is green.

Status: planned for v1.7 as “Diff boundary and staging interception”; not
implemented in v1.6.1.

### u/QuanTradin

Known pain points/advice:

- A low-privilege account can read a scratch directory and send data out;
  egress needs a service-account network allowlist.
- The first blocked connection log is valuable and must not be silent.
- Approval fatigue can be reduced by free writes in a staging area and TOTP
  only when moving into the real workspace.

Status: v1.6.1 ships Scoped Token (30-minute directory authorization) to reduce
approval fatigue. Outbound firewall audit and staging-to-production
interception are planned for v1.6.2, not shipped yet.

### u/Practical-Craft4967

Known pain points/advice:

- A TOTP prompt that shows only the AI’s natural-language description is not a
  security surface.
- It must show the real tool-call parameters: absolute path, action, recursion.

Status: implemented in the Broker approval path; prompts carry the real target
path and action instead of an AI-written summary.

### u/More-Ad7285

Known pain points/advice:

- Repeated TOTP prompts are exhausting; an operator actively watching the agent
  needs a short auto-approval path.

Status: v1.6.1 implements `SCOPED 30` directory authorization, a broader but
time-bounded mechanism than a 30-second auto-approval.

### u/HeartMaleficent35

Known pain points/advice:

- Appreciation for fail-closed behavior; most consumer tools fail open and
  apologize afterwards.

Status: fail-closed is the governing rule across ACL, Broker, and the DSH gate.

> Roadmap items above are commitments of intent, not shipped v1.6.1 features.
> See [STATUS_v1.6.1.md](../STATUS_v1.6.1.md) for the authoritative list.
