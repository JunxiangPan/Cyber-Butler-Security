Option Explicit
' Launch the WPF installer without leaving a PowerShell console window.
' ShellExecute with the runas verb requests UAC; window style 0 keeps the
' PowerShell host hidden while the WPF window remains visible.
Dim fso, shell, baseDir, guiPath, arguments
Set fso = CreateObject("Scripting.FileSystemObject")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
guiPath = baseDir & "\CyberButler.Installer.GUI.ps1"
arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & guiPath & """"
Set shell = CreateObject("Shell.Application")
shell.ShellExecute "powershell.exe", arguments, baseDir, "runas", 0
