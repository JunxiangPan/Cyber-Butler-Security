@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File','%~dp0CyberButler.Installer.GUI.ps1')"
endlocal
