@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0installer\CyberButler.Installer.GUI.ps1"
exit /b %ERRORLEVEL%
