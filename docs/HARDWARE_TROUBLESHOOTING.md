# 硬件故障排查：NVIDIA `VIDEO_TDR_ERROR`（0x116）

> 适用症状：关闭显示器后电脑突然重启、黑屏后自动开机、事件日志出现 `nvlddmkm` 错误和 `BugCheck 0x116`。  
> **这不是 Windows 睡眠。** 这是显卡驱动/硬件在显示电源切换时发生 TDR（Timeout Detection and Recovery）崩溃。

## 1. 先确认证据

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,1001,6008} -MaxEvents 20 |
  Format-List TimeCreated,Id,ProviderName,Message

Get-ChildItem C:\Windows\Minidump -Filter *.dmp |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 Name,Length,LastWriteTime
```

典型记录：

```text
nvlddmkm Error
BugCheck 0x00000116 (VIDEO_TDR_ERROR)
Kernel-Power 41
```

当前机器最近的转储：

```text
C:\Windows\Minidump\102926-26703-01.dmp
```

## 2. 驱动彻底清理重装

1. 创建系统还原点。
2. 下载官方 NVIDIA 驱动（建议先用 Studio/Game Ready 的稳定版本）。
3. 断网或暂停 Windows Update 自动驱动更新。
4. 使用 **DDU（Display Driver Uninstaller）**：
   - 重启进入安全模式；
   - 选择 NVIDIA，执行 **Clean and restart**；
5. 安装刚下载的官方驱动，选择“自定义安装”；
6. 安装完成后重启，观察是否仍有 `nvlddmkm` 事件。

不要用第三方“驱动大师”覆盖安装。

## 3. 恢复显卡默认状态

如果使用 MSI Afterburner、Fan Control、显卡超频/降压：

- 核心频率、显存频率、功耗墙全部恢复默认；
- 删除开机自动应用的超频配置；
- 如果有“曲线降压”，先完全关闭；
- 观察 24 小时，再决定是否重新做小幅降压。

`0x116` 对显存/核心不稳定非常敏感。

## 4. 检查 4090 供电

- 12VHPWR 接口重新插紧，确认卡扣到位；
- 优先使用电源原生 12VHPWR 线；
- 不要使用劣质转接线或一分二转接；
- 确认电源功率和 12V 联合输出足够；
- 检查显卡端和电源端是否有发热、变色、松动。

## 5. 检查显示器链路

关闭显示器时触发，重点排查 DP/HDMI 链路：

- 换一根认证的 DisplayPort 线；
- 换显卡上的另一个 DP 口；
- 暂时改用 HDMI 测试；
- 关闭显示器 HDR / DSC / 高刷新率做对照；
- 更新显示器固件（如有）。

## 6. PCIe 与电源管理

以管理员 PowerShell 执行：

```powershell
# 高性能电源计划
powercfg /setactive SCHEME_MIN

# 关闭 PCIe 链接状态电源管理（AC）
powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0
powercfg /setactive SCHEME_CURRENT
```

NVIDIA 控制面板：

```text
电源管理模式：优先最高性能
```

BIOS 中可检查：

- PCIe 速率设为 Auto/Gen4，不要强制不稳定的 Gen5；
- Resizable BAR / Above 4G 保持稳定设置；
- 关闭不必要的极端超频/内存 EXPO 做对照。

## 7. 不要用这些“修复”掩盖问题

不建议：

- 把 `TdrDelay` 调得很大来避免蓝屏；
- 关闭 TDR；
- 通过“禁止显示器休眠”来掩盖驱动崩溃；
- 用第三方超频软件继续加压。

TDR 是保护机制，绕过它只会让问题更难定位。

## 8. 如果仍然复现

按顺序做：

1. 换 NVIDIA 驱动版本（回退一个稳定版）；
2. 换显示器/线材/接口；
3. 拔掉非必要 USB/PCIe 设备；
4. 检查内存 EXPO/XMP 稳定性（MemTest86）；
5. 用另一张显卡或另一台机器交叉测试；
6. 仍复现则考虑显卡/电源 RMA。

## 9. 本次事件与 Bot 的关系

本次是 GPU 驱动崩溃导致系统重启，不是 Bot 把电脑休眠。

系统重启后：

```text
Ollama 尚未加载模型
→ cloud_fallback 误判
→ 会话切到 deepseek
```

现在 `cloud_fallback` 已加入 **90 秒启动宽限期**，并修复了配置 BOM 读取问题；本地模型就绪后会继续使用 `local_qwen36`。
