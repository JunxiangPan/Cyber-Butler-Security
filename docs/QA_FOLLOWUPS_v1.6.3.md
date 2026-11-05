# QA follow-ups — v1.6.3

## Open: self-contained installer shell exits silently

Observed on a clean VM:

- The 35 MB self-contained `START-INSTALLER.exe` exits with code 0 and shows no window.
- Running `powershell.exe -ExecutionPolicy Bypass -File .\installer\CyberButler.Installer.GUI.ps1`
  directly opens the installer GUI normally.
- The Python/PowerShell install logic is therefore not implicated.

Known-good workaround used for VM acceptance: launch the GUI script directly from an
administrator PowerShell session.

Required v1.6.4 fix:

1. Reproduce on a clean VM with the self-contained single-file build.
2. Inspect the single-file launch path: elevation relaunch, `Environment.ProcessPath`,
   working directory, `Process.Start`, and exit-code propagation.
3. Add a Pester or VM smoke test that asserts the C# shell leaves a visible GUI process
   running and does not exit 0 before the GUI appears.
4. Do not call the C# shell fixed until that VM test passes.
