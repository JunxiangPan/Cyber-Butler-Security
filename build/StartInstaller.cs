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
        string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine;
        try
        {
            string logDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "logs");
            Directory.CreateDirectory(logDir);
            File.AppendAllText(Path.Combine(logDir, "installer.log"), line);
        }
        catch
        {
            try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "CyberButler-installer-shell.log"), line); }
            catch { }
        }
    }

    private static int RunGui(string gui)
    {
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = "-NoProfile -STA -ExecutionPolicy RemoteSigned -File \"" + gui + "\"";
        psi.WorkingDirectory = Path.GetDirectoryName(gui);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        Log("starting PowerShell with ExecutionPolicy RemoteSigned gui=" + gui);
        using (Process child = Process.Start(psi))
        {
            if (child == null) { Log("Process.Start returned null"); return 4; }
            child.OutputDataReceived += (sender, args) => { if (!string.IsNullOrEmpty(args.Data)) Log("stdout: " + args.Data); };
            child.ErrorDataReceived += (sender, args) => { if (!string.IsNullOrEmpty(args.Data)) Log("stderr: " + args.Data); };
            child.BeginOutputReadLine();
            child.BeginErrorReadLine();
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
