# Clean-VM acceptance — v1.6.2-final17

Run on a clean Windows 10/11 x64 VM, logged in as the desktop account that will own the install.

## 1. Install

```powershell
# Extract the package, then run as administrator:
.\START-INSTALLER.exe
```

- Install path: `C:\CyberButler`
- Tier: `High`
- WebUI bind: `Loopback`
- Personal plugins path: leave blank for a clean install
- API Key / SMTP: leave blank unless explicitly testing those flows
- TOTP: scan and store recovery codes offline

## 2. Acceptance

Run as administrator from the extracted package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File '.\tools\clean-vm-acceptance.ps1' `
  -InstallPath 'C:\CyberButler' `
  -ConfigPath '.\docs\_data\clean-vm-expected.json'
```

The result must have:

```text
"ok": true
"problems": []
"installer_report": { "status": "success" }
```

## 3. Manual checks

```powershell
Get-Content 'C:\CyberButler\VERSION' -Raw
Get-Service CyberButlerAstrBot
Get-NetTCPConnection -State Listen |
  Where-Object { $_.LocalPort -in 6185,18090,8765,8766,5099 }
```

Open:

```text
http://127.0.0.1:8765/
```

Check the SnowLuma card:

- If `SnowLuma\logs\startup-snowluma.out.log` contains `initial credentials`, the password is displayed after `[显示]`.
- If not, the card shows the red manual guidance. CBS does not reset SnowLuma.
- OneBot Token has its own `[显示] [复制]` controls.

Check the game-mode runtime:

```text
%LOCALAPPDATA%\CyberButler\game-mode
```

There must be no new game-mode files under the Desktop.

## 4. Uninstall

Run the installer as administrator and choose the project removal. The uninstaller now stops and deletes `CyberButlerAstrBot` before removing its binary, and removes:

```text
C:\CyberButler
C:\ProgramData\CyberButler
%LOCALAPPDATA%\CyberButler\game-mode
```

It must leave no SCM service registration and no game-mode desktop folder.
