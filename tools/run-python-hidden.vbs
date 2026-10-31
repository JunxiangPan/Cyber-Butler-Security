Option Explicit
' Hidden Python launcher for scheduled tasks.
' Usage: wscript.exe //B run-python-hidden.vbs "<python.exe>" "<script>" "<workdir>"
If WScript.Arguments.Count < 3 Then WScript.Quit 2

Dim pythonPath, scriptPath, workDir, commandLine, shell, exitCode
pythonPath = WScript.Arguments(0)
scriptPath = WScript.Arguments(1)
workDir = WScript.Arguments(2)

Set shell = CreateObject("WScript.Shell")
shell.CurrentDirectory = workDir
commandLine = Chr(34) & pythonPath & Chr(34) & " " & Chr(34) & scriptPath & Chr(34)
exitCode = shell.Run(commandLine, 0, True)
WScript.Quit exitCode
