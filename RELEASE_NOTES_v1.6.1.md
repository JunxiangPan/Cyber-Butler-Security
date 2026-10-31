# v1.6.1 - Installer Reliability and Visual Setup

v1.6.1 focuses on the clean-install path: the Web UI launcher now resolves the production layout, creates its mailer token when missing, and keeps the Web UI available when the optional OTP mailer cannot start. It also adds a WPF front-end and the updater metadata fix needed by production merges.

⚠️ Note: A v1.5.3 installation must use the full installer to cross the release-key and overlay-format change. The legacy updater and the v1.6.0 merge path are not a supported bootstrap route.

🔧 Installer Reliability

**Web UI root**: `start-services.ps1` now detects both the production `webui` layout and the `public-release` layout before resolving `webui-config.json`.

**Mailer token**: a missing `webui\data\mailer_token` is generated as 32 random bytes encoded as 64 hex characters; an existing token is preserved.

**Non-blocking OTP**: an OTP mailer failure is logged as a warning and no longer prevents the Web UI from starting or aborts the whole service assertion.

**Config fallback**: a `webui\config.json` layout is accepted when the root-level `webui-config.json` is absent.

🖥️ Visual Installer

**WPF front-end**: `installer\CyberButler.Installer.GUI.ps1` collects the install path, tier, owner QQ, WebUI bind, optional personal-plugins path, and optional API-key file. The UI has Chinese and English labels and runs the installer as a hidden child process; TOTP enrollment is a WPF dialog with the QR image and recovery codes.

**Preflight in the UI**: the GUI can run a read-only environment preflight and display its JSON result.

**Explicit approval**: the GUI requires an explicit approval checkbox before it supplies the approval tokens. It never auto-approves silently.

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

Relevant pytest: 18 passed.

⚠️ Known Limitations

Clean Windows 11 Pro VM end-to-end acceptance has not yet been run for this draft.

The visual installer is a front-end and preflight tool, not a fully silent unattended installer. The first installation still requires a UAC-elevated GUI and explicit approval/TOTP interaction.

`update_merge.ps1` still needs a dedicated `webui\.venv` bootstrap/check for targets where that virtual environment is absent.

The release package has not yet been rebuilt or signed for this version.

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

**WPF 前端**：`installer\CyberButler.Installer.GUI.ps1` 收集安装路径、Tier、Owner QQ、WebUI 绑定、可选个人插件路径和可选 API key 文件。界面支持中文/英文，安装器作为隐藏子进程运行；TOTP 注册使用带 QR 和恢复码的 WPF 对话框。

**界面内预检**：GUI 可以运行只读环境预检并显示 JSON 结果。

**显式批准**：GUI 只有在用户勾选批准后才提供 approval token，不会静默自动批准安全步骤。

🛡️ 更新完整性

**Overlay metadata**：`update_merge_core.py` 将 `overlay/overlay-manifest.json` 作为发布元数据跳过，不再把它当作 AstrBot 运行时 overlay 目标。

**公钥放行**：更新器 allowlist 接受 `tools/update_pubkey.pem`；其他 `.pem` 继续拒绝。

**TOTP 运行路径**：Broker 现在解析 `tools/totp-vault/totp_secret.dpapi` 和 `recovery_hashes.json`，并兼容旧的根路径。

**Broker ACL**：安装器在 TOTP 注册前硬化 `tools` 和 `AstrBot/.venv`。单账户 Medium 模式会在 `single-account.marker` 中记录无法强制 TOTP vault Deny 的限制；High 隔离仍要求显式 Deny。AstrBot 和 WebUI 通过 `tools/run-python-hidden.vbs` 的无控制台 WSH 启动器运行；Broker 优先使用 `pythonw.exe`。桌面不会残留控制台窗口。

**WebUI 数据保护**：更新器保护范围增加 `webui/data/mailer_token` 和 TOTP vault 文件。

**语言**：可视化安装器支持中文/英文界面标签。

**版本**：仓库版本更新为 `1.6.1`。

✅ 验证

主机 Pester：144 passed，0 failed。

GUI XAML 自检：`GUI_XAML_OK`。

相关 pytest：18 passed。

⚠️ 已知限制

本草案尚未在干净 Windows 11 Pro VM 上完成端到端验收。

可视化安装器是前端和预检工具，不是完全静默的无人值守安装器；首次安装仍需要提权 GUI 和显式批准/TOTP 操作。

`update_merge.ps1` 仍需要补上 `webui\.venv` 的专用创建/检查逻辑，以覆盖虚拟环境缺失的目标机。

本版本的发布包尚未重新构建或签名。

AstrBot 和 Web UI 仍是 Interactive 计划任务；注销桌面会话仍可能终止它们。无人值守部署需要自动登录策略或非交互服务模式。
