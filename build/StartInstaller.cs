using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;

[assembly: AssemblyTitle("Cyber-Butler Installer")]
[assembly: AssemblyDescription("Installer entry point (PowerShell 7 shell, no in-process PowerShell dependency)")]
[assembly: AssemblyCompany("Cyber-Butler")]
[assembly: AssemblyProduct("Cyber-Butler Security")]
[assembly: AssemblyFileVersion("1.6.4.0")]
[assembly: AssemblyVersion("1.6.4.0")]

internal static class InstallerProgram
{
    private const string PwshMissingMessage = "CBS requires PowerShell 7. Please install it from Microsoft.";

    private static bool IsAdministrator()
    {
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
        }
    }

    private static void AppendLog(string directory, string message)
    {
        string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine;
        try
        {
            string logDir = Path.Combine(directory, "logs");
            Directory.CreateDirectory(logDir);
            File.AppendAllText(Path.Combine(logDir, "installer.log"), line);
        }
        catch
        {
            try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "CyberButler-installer-shell.log"), line); }
            catch { }
        }
    }

    private static void Log(string message)
    {
        AppendLog(AppDomain.CurrentDomain.BaseDirectory, message);
    }

    private static void ShowFatal(string message)
    {
        try
        {
            MessageBox.Show(message, "Cyber-Butler Installer", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch
        {
            // The exit code and crash log remain the fallback when no UI is available.
        }
    }

    private static void Crash(string baseDir, Exception ex)
    {
        string detail = DateTime.Now.ToString("o") + Environment.NewLine +
                        ex.GetType().FullName + ": " + ex.Message + Environment.NewLine +
                        ex.StackTrace + Environment.NewLine;
        try { File.WriteAllText(Path.Combine(baseDir, "crash.log"), detail); }
        catch
        {
            try { File.WriteAllText(Path.Combine(Path.GetTempPath(), "CyberButler-installer-crash.log"), detail); }
            catch { }
        }
        AppendLog(baseDir, "CRASH: " + ex.GetType().Name + ": " + ex.Message);
        ShowFatal("CBS installer could not start." + Environment.NewLine + Environment.NewLine +
                  ex.GetType().Name + ": " + ex.Message + Environment.NewLine +
                  "A crash.log was written next to START-INSTALLER.exe.");
    }

    private static string FindPwsh()
    {
        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string[] candidates =
        {
            Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe"),
            Path.Combine(programFiles, "PowerShell", "7-preview", "pwsh.exe"),
            Path.Combine(localAppData, "Microsoft", "WindowsApps", "pwsh.exe"),
        };
        foreach (string candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }
        // Final fallback: let CreateProcess search PATH. A missing executable is
        // caught and converted into the friendly PowerShell 7 prompt below.
        return "pwsh.exe";
    }

    private static int RelaunchAsAdministrator(string baseDir)
    {
        string selfPath = Environment.ProcessPath;
        if (string.IsNullOrEmpty(selfPath))
        {
            Process current = Process.GetCurrentProcess();
            selfPath = current.MainModule == null ? "" : current.MainModule.FileName;
        }
        if (string.IsNullOrEmpty(selfPath) || !File.Exists(selfPath))
        {
            throw new FileNotFoundException("Cannot locate START-INSTALLER.exe for elevation.");
        }
        ProcessStartInfo self = new ProcessStartInfo();
        self.FileName = selfPath;
        self.UseShellExecute = true;
        self.Verb = "runas";
        Log("requesting administrator elevation");
        try
        {
            Process.Start(self);
            return 0;
        }
        catch (Win32Exception ex)
        {
            // 1223 is ERROR_CANCELLED: the user declined the UAC prompt.
            AppendLog(baseDir, "elevation declined or unavailable: " + ex.NativeErrorCode);
            ShowFatal("Administrator permission is required to install CBS.");
            return 8;
        }
    }

    private static int RunGui(string gui, string baseDir)
    {
        string pwsh = FindPwsh();
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = pwsh;
        psi.Arguments = "-NoProfile -STA -ExecutionPolicy RemoteSigned -File \"" + gui + "\"";
        psi.WorkingDirectory = Path.GetDirectoryName(gui);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        AppendLog(baseDir, "starting PowerShell 7 (" + pwsh + ") gui=" + gui);
        Process child;
        try
        {
            child = Process.Start(psi);
        }
        catch (Exception ex)
        {
            AppendLog(baseDir, "cannot start PowerShell 7: " + ex.GetType().Name + ": " + ex.Message);
            ShowFatal(PwshMissingMessage);
            return 7;
        }
        using (child)
        {
            if (child == null)
            {
                AppendLog(baseDir, "Process.Start returned null");
                ShowFatal(PwshMissingMessage);
                return 7;
            }
            child.OutputDataReceived += (sender, args) => { if (!string.IsNullOrEmpty(args.Data)) AppendLog(baseDir, "stdout: " + args.Data); };
            child.ErrorDataReceived += (sender, args) => { if (!string.IsNullOrEmpty(args.Data)) AppendLog(baseDir, "stderr: " + args.Data); };
            child.BeginOutputReadLine();
            child.BeginErrorReadLine();
            child.WaitForExit();
            AppendLog(baseDir, "PowerShell exited code=" + child.ExitCode);
            return child.ExitCode;
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        string baseDir = "";
        try
        {
            baseDir = AppDomain.CurrentDomain.BaseDirectory;
            Log("START-INSTALLER boot");
            string gui = Path.Combine(baseDir, "installer", "CyberButler.Installer.GUI.ps1");
            if (!File.Exists(gui))
            {
                AppendLog(baseDir, "GUI entry point missing: " + gui);
                ShowFatal("CBS installer payload is incomplete: installer\\CyberButler.Installer.GUI.ps1 is missing.");
                return 3;
            }
            if (!IsAdministrator())
            {
                return RelaunchAsAdministrator(baseDir);
            }
            return RunGui(gui, baseDir);
        }
        catch (Exception ex)
        {
            Crash(string.IsNullOrEmpty(baseDir) ? AppDomain.CurrentDomain.BaseDirectory : baseDir, ex);
            return 6;
        }
    }
}
