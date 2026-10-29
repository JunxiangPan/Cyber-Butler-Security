Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(base, "update_gui.ps1")
cmd = "powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
CreateObject("WScript.Shell").Run cmd, 0, False
