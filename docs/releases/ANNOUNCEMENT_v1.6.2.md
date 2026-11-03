> **Historical / superseded.** This file is retained for history only. The current release is `docs/releases/RELEASE_NOTES_v1.6.2.md` (SCM service release). Do not use this preview as current installation guidance.

# ⚠️ v1.6.2 Experimental Preview — DO NOT USE FOR NORMAL INSTALLATION

> Community acknowledgements: [CONTRIBUTORS.md](../../CONTRIBUTORS.md)

> 这是一份先导版/实验版，不是稳定版，不是生产版，也不是给普通用户直接使用的版本。
>
> **如果你只是想让 Cyber-Butler 正常工作，请下载 v1.6.1，不要从这个 v1.6.2 包开始。**

## 先导版声明

v1.6.2 包目前**没有经过任何干净 VM 的完整安装/卸载验收，也没有经过真实物理机的完整运行验收**。

已经完成的只有：

```text
开发环境 pytest
Pester 安装器测试
privacy scan
代码级安全检查
```

这些测试只能说明有限范围内的代码行为，**不能证明**：

```text
安装器在干净 Windows 上一定成功
AstrBot/SnowLuma 一定能启动
QQ 登录/反向 WS 一定可用
WFP/Tripwire 在真实网络环境下一定正确
卸载不会残留
升级/回滚一定安全
```

因此：

> **不要在日常使用的主机上直接运行这个包。**
>
> 如果要测试，请使用：
>
> - 一次性 Windows VM；
> - 或先创建完整磁盘快照/还原点；
> - 不要使用真实 QQ、真实 API Key、真实邮箱授权码；
> - 不要把它当作已经验证的安全产品。

## 正常使用请下载 v1.6.1

普通用户/正常安装请使用：

```text
v1.6.1
```

v1.6.1 是当前已实际测试并经过 VM/实机验证的基线版本。  
其中 **High 档已经完成实际运行验收**；Medium/Light 档的测试仍不完整，不能把 v1.6.1 的所有档位都描述成同等稳定。

v1.6.0 已经过时，不再作为推荐下载版本。

不要因为 v1.6.2 版本号更高就认为它更稳定。  
它是用于发现 bug、复现问题和验证新边界的先导版。

## 这个版本包含什么

v1.6.2 是安全加固预览，包含：

- TOCTOU/句柄绑定和 quarantine
- 内容感知审批、Magic Bytes（Shebang/PE/ELF）
- Intent Mismatch 警告
- Critical Integrity Files 硬拒绝
- TOTP 限速与拒绝 jitter
- Job Object 资源限制
- WFP-backed audit-only 出站策略与日志 Tripwire
- 端口 18090 防劫持
- 审计哈希链 sidecar
- Watchdog fail-closed
- SBOM bundle
- WebUI 网络放行表单
- Credential Proxy（实验模块）
- External-read / 间接提示词注入提醒（实验模块）
- 物理隔离安装提示
- 卸载顺序加固

## 明确没有完成/不能宣称的部分

```text
native WFP filter API 尚未完成
审计链尚未全量替换 Broker 所有旧写入
Light 档没有完整实机验收
AppContainer 未实现
Credential Proxy 尚未接入安装器服务
外部读取上报需要 Agent/插件主动调用
```

WFP 当前是**audit-only/firewall-backed**，不是 native WFP filter。  
在实机确认前，不要切换到 enforce。

## 签名与校验

发布资产：

```text
public-release-v1.6.2.zip
sha256 = 124be0d10bb6b0a14a4b790e388a9db1ee87ef8f53bb296282a5d3084d0ddd1b

update-manifest.json
sha256 = b075ca3f7a246878350dbf304411c565e2f8a011a6bb13a4ffd4ba4e6fe6d813

update-manifest.sig
sha256 = 57a829f572647a6389218e61b9fd679fb5db055f20e9a05649c2b5c195830f78

update_pubkey.pem
sha256 = 2309d4ac5ba9dadc2300a3f5d038fbbcee8f81507479e9cc246b6ed77b033398
```

校验命令：

```powershell
python tools/verify_release.py `
  --manifest update-manifest.json `
  --signature update-manifest.sig `
  --pubkey update_pubkey.pem
```

必须输出：

```text
VALID
```

签名只证明 manifest 与发布密钥匹配，**不证明**这个版本已经过实机安全验收。

## 希望测试者反馈什么

请优先报告“能复现的问题”，而不是只说“不能用”：

```text
Windows 版本和 build
CPU/内存/是否有独显
安装档位 High / Medium / Light
安装路径
是否干净 VM/是否有旧版
从哪个步骤开始失败
完整错误文本
是否可重复
最小复现步骤
脱敏后的日志
```

不要上传：

```text
TOTP secret / 恢复码
真实 API Key
邮箱授权码
QQ 凭据
私钥
```

安全漏洞请不要公开贴出利用细节，按 `SECURITY.md` 的 GitHub Security Advisory 流程报告。

## 测试目标

v1.6.2 先导版的目标不是“让所有人升级”，而是：

- 找出干净 VM 安装失败点；
- 找出 AstrBot/SnowLuma 启动问题；
- 找出 WFP/Tripwire 误报/漏报；
- 找出卸载残留和卡死；
- 找出审批/Intent Mismatch 的误报；
- 找出真实 QQ/API Key 集成问题；
- 收集可复现的 bug 报告。

在没有完成这些实机验收之前，请不要把 v1.6.2 标记为 stable，也不要推荐普通用户使用。
