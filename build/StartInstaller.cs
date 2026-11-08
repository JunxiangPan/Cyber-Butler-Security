using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;

[assembly: AssemblyTitle("Cyber-Butler Installer")]
[assembly: AssemblyDescription("Installer entry point (PowerShell fallback shell, no in-process PowerShell dependency)")]
[assembly: AssemblyCompany("Cyber-Butler")]
[assembly: AssemblyProduct("Cyber-Butler Security")]
[assembly: AssemblyFileVersion("1.6.3.0")]
[assembly: AssemblyVersion("1.6.3.0")]

internal static class InstallerProgram
{
    private static bool IsAdministrator()
    {
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
        }
    }

    private static void Log(string message)
    {
        try
        {
            File.AppendAllText(Path.Combine(Path.GetTempPath(), "CyberButler-installer-shell.log"),
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine);
        }
        catch { }
    }

    private static int RunGui(string gui)
    {
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + gui + "\"";
        psi.WorkingDirectory = Path.GetDirectoryName(gui);
        psi.UseShellExecute = true;
        psi.CreateNoWindow = false;
        psi.WindowStyle = ProcessWindowStyle.Normal;
        Log("starting PowerShell with ExecutionPolicy Bypass gui=" + gui);
        using (Process child = Process.Start(psi))
        {
            if (child == null) { Log("Process.Start returned null"); return 4; }
            child.WaitForExit();
            Log("PowerShell exited code=" + child.ExitCode);
            return child.ExitCode;
        }
    }

    private static int Main(string[] args)
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string gui = Path.Combine(baseDir, "installer", "CyberButler.Installer.GUI.ps1");
        if (!File.Exists(gui)) return 3;
        if (!IsAdministrator())
        {
            ProcessStartInfo self = new ProcessStartInfo();
            self.FileName = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule.FileName;
            self.UseShellExecute = true;
            self.Verb = "runas";
            Process.Start(self);
            return 0;
        }
        try
        {
            return RunGui(gui);
        }
        catch (Exception ex)
        {
            Log("installer shell exception: " + ex.GetType().Name + ": " + ex.Message);
            return 6;
        }
    }
}
