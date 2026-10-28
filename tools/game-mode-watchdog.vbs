' Hidden launcher for Game Mode Watchdog.
' Task Scheduler starts wscript.exe, which has no console window. The
' PowerShell child is launched with window style 0 (hidden).
Option Explicit
Dim fso, shell, folder, script, command
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(folder, "game-mode-watchdog.ps1")
command = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden " & _
          "-ExecutionPolicy Bypass -File """ & script & """"
shell.Run command, 0, True
