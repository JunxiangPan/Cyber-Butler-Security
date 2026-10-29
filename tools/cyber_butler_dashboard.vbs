Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(base, "cyber_butler_dashboard.ps1")
project = ""
If WScript.Arguments.Count > 0 Then project = WScript.Arguments(0)
cmd = "powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
If project <> "" Then cmd = cmd & " -ProjectRoot """ & project & """"
CreateObject("WScript.Shell").Run cmd, 0, False
