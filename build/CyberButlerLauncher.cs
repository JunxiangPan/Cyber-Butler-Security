using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Reflection;
using System.Security.Principal;
using System.Threading;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

[assembly: AssemblyTitle("Cyber-Butler Launcher")]
[assembly: AssemblyDescription("Hidden/native launcher for Cyber-Butler services and installers")]
[assembly: AssemblyCompany("Cyber-Butler")]
[assembly: AssemblyProduct("Cyber-Butler Security")]
[assembly: AssemblyFileVersion("1.6.3.0")]
[assembly: AssemblyVersion("1.6.3.0")]

internal static class Program
{
    private static int Main(string[] args)
    {
        // Double-clicking START-INSTALLER.exe has no arguments. Treat that as
        // the installer entry point rather than exiting silently.
        if (args.Length == 0)
        {
            args = new string[] { "--installer" };
        }

        string exe = "";
        string workdir = "";
        string childArgs = "";
        string logPath = "";
        bool hidden = false;
        bool elevate = false;
        bool wait = false;
        bool installer = false;
        int delaySeconds = 0;

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--exe":
                    if (++i >= args.Length) return 2;
                    exe = args[i];
                    break;
                case "--workdir":
                    if (++i >= args.Length) return 2;
                    workdir = args[i];
                    break;
                case "--args":
                    if (++i >= args.Length) return 2;
                    childArgs = args[i];
                    break;
                case "--log":
                    if (++i >= args.Length) return 2;
                    logPath = args[i];
                    break;
                case "--delay":
                    if (++i >= args.Length) return 2;
                    delaySeconds = int.Parse(args[i]);
                    break;
                case "--hidden":
                    hidden = true;
                    break;
                case "--elevate":
                    elevate = true;
                    break;
                case "--wait":
                    wait = true;
                    break;
                case "--installer":
                    installer = true;
                    break;
                default:
                    return 2;
            }
        }

        if (installer)
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string installerDir = Path.Combine(baseDir, "installer");
            string gui = Path.Combine(installerDir, "CyberButler.Installer.GUI.ps1");
            if (!File.Exists(gui)) return 3;
            if (!IsAdministrator())
            {
                ProcessStartInfo self = new ProcessStartInfo();
                self.FileName = Assembly.GetEntryAssembly().Location;
                self.Arguments = "--installer";
                self.UseShellExecute = true;
                self.Verb = "runas";
                Process.Start(self);
                return 0;
            }
            return RunInstallerGui(gui, installerDir);
        }

        if (exe.Length == 0 || workdir.Length == 0) return 2;
        if (delaySeconds > 0) Thread.Sleep(delaySeconds * 1000);

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = exe;
        psi.Arguments = childArgs;
        psi.WorkingDirectory = workdir;
        psi.WindowStyle = ProcessWindowStyle.Hidden;

        if (elevate)
        {
            psi.UseShellExecute = true;
            psi.Verb = "runas";
        }
        else
        {
            psi.UseShellExecute = false;
            psi.CreateNoWindow = hidden;
            if (logPath.Length > 0)
            {
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
            }
        }

        using (Process process = Process.Start(psi))
        {
            if (process == null) return 4;

            StreamWriter writer = null;
            if (!elevate && logPath.Length > 0)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logPath));
                writer = new StreamWriter(logPath, true, Encoding.UTF8);
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data != null)
                    {
                        lock (writer) { writer.WriteLine(e.Data); writer.Flush(); }
                    }
                };
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data != null)
                    {
                        lock (writer) { writer.WriteLine(e.Data); writer.Flush(); }
                    }
                };
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }

            if (wait) process.WaitForExit();
            if (writer != null)
            {
                try { writer.Flush(); writer.Close(); } catch { }
            }
            return wait ? process.ExitCode : 0;
        }
    }

    private static bool IsAdministrator()
    {
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            WindowsPrincipal principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
    }

    private static int RunInstallerGui(string gui, string workdir)
    {
        try
        {
            Runspace runspace = RunspaceFactory.CreateRunspace();
            runspace.ApartmentState = ApartmentState.STA;
            runspace.Open();
            using (PowerShell ps = PowerShell.Create())
            {
                ps.Runspace = runspace;
                ps.AddCommand(gui);
                ps.Invoke();
                if (ps.HadErrors) { return 5; }
            }
            return 0;
        }
        catch { return 6; }
    }
}
