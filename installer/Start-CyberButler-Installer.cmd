@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0CyberButler.Installer.GUI.ps1"
if errorlevel 1 pause
endlocal
