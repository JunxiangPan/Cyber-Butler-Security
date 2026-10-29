# Tailscale 外网安全接入 Web 面板

目标：手机在公司/外面用蜂窝网络访问家里的 Cyber-Butler Web 面板和“大肥鱼文件”，
**不开放路由器端口、不做公网端口映射**。

最终地址形式：

```text
http://100.x.x.x:8765
```

或（可选，Tailscale Serve HTTPS）：

```text
https://<电脑名>.<你的 tailnet>.ts.net
```

---

## 0. 先确认 Web 服务监听

本机 `webui-config.json` 必须是：

```json
"host": "0.0.0.0",
"port": 8765,
"cookie_secure": "auto"
```

`0.0.0.0` 不是“公网开放”，只是允许本机所有网卡（局域网、Tailscale）连接；
真正的公网入口不存在，因为路由器没有做端口转发。

Windows 防火墙需要两条入站规则：

- `Cyber-Butler Web UI (LAN)`：TCP 8765，仅 LocalSubnet；
- `Cyber-Butler Web UI (Tailscale)`：TCP 8765，仅 `100.64.0.0/10`。

管理员 PowerShell 检查：

```powershell
Get-NetFirewallRule -DisplayName 'Cyber-Butler Web UI*' |
  Select-Object DisplayName,Enabled,Direction,Action,Profile
```

---

## 1. Windows 电脑安装 Tailscale

### 1.1 安装

官方下载页：

```text
https://tailscale.com/download/windows
```

或直接下载安装包：

```text
https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe
```

双击安装，安装程序会注册 `Tailscale` 服务并启动。

检查：

```powershell
Get-Service Tailscale
& 'C:\Program Files\Tailscale\tailscale.exe' version
```

### 1.2 登录

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' up
```

它会打印一个 `https://login.tailscale.com/a/...` 地址，并在浏览器打开。
用你的 Tailscale 账号登录（推荐 Google/Microsoft/GitHub 中你常用的那个）。
登录完成后，电脑就会加入你的 tailnet。

### 1.3 查看虚拟 IP

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' status
& 'C:\Program Files\Tailscale\tailscale.exe' ip -4
```

输出类似：

```text
100.101.102.103
```

这个 `100.x.x.x` 就是手机要访问的地址。它不是公网 IP，不能从没有加入
tailnet 的设备访问。

### 1.4 查看 MagicDNS 名称（可选）

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' status --json
```

在返回 JSON 里找：

```json
"DNSName": "pcvp.tailxxxx.ts.net."
```

去掉末尾的点，就是稳定的域名。MagicDNS 开启时，手机也可以用这个域名。

---

## 2. 手机安装 Tailscale

### iPhone / iPad

1. App Store 搜索 **Tailscale**；
2. 安装后打开，点 **Sign in**；
3. 用**和电脑同一个 Tailscale 账号**登录；
4. 打开顶部开关，状态应为 **Connected**。

### Android

1. Google Play 搜索 **Tailscale**；
2. 安装后打开，点 **Sign in**；
3. 用同一个账号登录；
4. 打开 VPN 开关，通知栏出现 Tailscale 已连接。

> 手机登录的必须是同一个 tailnet。不同账号/不同 tailnet 的设备互相看不见。

---

## 3. 手机用蜂窝网络访问

1. 手机关闭 Wi-Fi（只用 4G/5G）；
2. 确认手机 Tailscale 是 **Connected**；
3. 浏览器输入：

```text
http://100.x.x.x:8765
```

例如电脑的 Tailscale IP 是 `100.101.102.103`：

```text
http://100.101.102.103:8765
```

4. 输入管理员邮箱，收 OTP，登录；
5. 打开“我的大肥鱼文件”，点文件预览/下载。

如果电脑同时开着局域网和 Tailscale，**手机用蜂窝网络时不要用
`192.168.1.111:8765`**，那个地址在蜂窝网络下不可达；请用 `100.x.x.x`。

---

## 4. 可选：Tailscale Serve HTTPS（更推荐）

HTTP over Tailscale 已经被 WireGuard 加密，但浏览器地址栏仍是 `http://`。
如果希望有合法 HTTPS 证书和更干净的地址，用 Tailscale Serve：

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' serve --bg http://127.0.0.1:8765
& 'C:\Program Files\Tailscale\tailscale.exe' serve status
```

然后手机访问：

```text
https://<电脑名>.<你的 tailnet>.ts.net
```

不需要加 `:8765`，Tailscale 会反代到本机 8765。

此时 `webui-config.json` 的：

```json
"cookie_secure": "auto"
```

会在检测到 HTTPS/本机反代时给 Cookie 加 `Secure`；HTTP 下不加，避免
`http://100.x.x.x:8765` 登录后 Cookie 被浏览器丢弃。

查看/关闭 Serve：

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' serve status
& 'C:\Program Files\Tailscale\tailscale.exe' serve off
```

---

## 5. 关于“切换网络掉登录”

`cookie_secure: "auto"` 解决的是 **HTTP/HTTPS 切换时 Secure 标记不匹配** 的问题，
但不能让 Cookie 跨主机名共享：

- `http://192.168.1.111:8765` 和 `http://100.x.x.x:8765` 是两个不同的源；
- 浏览器会把登录 Cookie 分开存储；
- 因此从家里局域网切到外网 Tailscale，通常需要**重新收一次 OTP**；
- 这是浏览器的同源策略，不是登录失效 bug。

最省心的做法：**在家里也优先使用 Tailscale 地址**（手机 Tailscale 常开），
这样始终是同一个源，7 天会话不会因为切网络而丢。

如果使用 Tailscale Serve HTTPS，请固定使用
`https://<电脑名>.<tailnet>.ts.net`，不要和 `http://100.x.x.x:8765` 混用。

---

## 6. 安全边界

- 路由器**不要**做 8765 端口转发/端口映射/DMZ；
- 不要把 8765 暴露到公网安全组；
- Tailscale ACL 只允许自己的设备访问这台电脑的 8765；
- Tailscale 账号开启 MFA；
- 丢失手机后，在 Tailscale 管理后台移除该设备；
- Web 面板仍保持：邮箱 OTP、只读监控、固定主人聊天、只读文件沙盒；
- 文件 API 只允许 `list`/`download`，根目录锁定，路径逃逸 403，可执行文件隐藏/拦截，单文件 20MB；
- Web 端没有写入、删除、上传、还原或审批验证码输入。

---

## 7. 排障

### 手机打不开，但电脑本机 200

电脑上：

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' status
& 'C:\Program Files\Tailscale\tailscale.exe' ping 100.x.x.x
Test-NetConnection 100.x.x.x -Port 8765
```

- `tailscale ping` 不通：手机/电脑不在同一 tailnet，或 Tailscale 未连接；
- `ping` 通但 8765 不通：检查 `Cyber-Butler Web UI (Tailscale)` 防火墙规则；
- 电脑休眠：Tailscale 会离线，需唤醒电脑；
- 公司 Wi-Fi 拦截 UDP：Tailscale 会走 DERP 中继，可能更慢但可用；
- 浏览器仍开旧页面：强制刷新或换隐私窗口；
- `http://100.x` 登录后马上掉：确认没有误用 `https://100.x` 或混用局域网 IP；
- 文件下载 403：该文件扩展名被拦截、超过 20MB，或根目录配置不对。

### 查看 Tailscale 服务

```powershell
Get-Service Tailscale
& 'C:\Program Files\Tailscale\tailscale.exe' status
& 'C:\Program Files\Tailscale\tailscale.exe' netcheck
```
