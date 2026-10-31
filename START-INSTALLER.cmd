@echo off
setlocal
set "ROOT=%~dp0"
if not exist "%ROOT%installer\Start-CyberButler-Installer.vbs" (
  echo Installer launcher not found. Keep the release folder intact.
  pause
  exit /b 1
)
wscript.exe //B "%ROOT%installer\Start-CyberButler-Installer.vbs"
endlocal
