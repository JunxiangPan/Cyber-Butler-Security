' Hidden per-user startup launcher for Boot SelfCheck.
' Waits 120 seconds after login, then runs the self-check without a window.
Option Explicit
Dim shell, folder, script, command
Set shell = CreateObject("WScript.Shell")
folder = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
script = folder & "\boot-selfcheck.ps1"
WScript.Sleep 120000
command = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden " & _
          "-ExecutionPolicy Bypass -File """ & script & """"
shell.Run command, 0, False
