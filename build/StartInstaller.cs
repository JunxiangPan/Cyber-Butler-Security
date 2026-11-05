using System;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Security.Principal;
using System.Threading;

[assembly: AssemblyTitle("Cyber-Butler Installer")]
[assembly: AssemblyDescription("Installer entry point using an in-process PowerShell runspace")]
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

    private static int RunGui(string gui)
    {
        Runspace runspace = RunspaceFactory.CreateRunspace();
        runspace.ApartmentState = ApartmentState.STA;
        runspace.Open();
        using (PowerShell ps = PowerShell.Create())
        {
            ps.Runspace = runspace;
            ps.AddCommand(gui);
            ps.Invoke();
            return ps.HadErrors ? 5 : 0;
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
            self.FileName = Assembly.GetEntryAssembly().Location;
            self.UseShellExecute = true;
            self.Verb = "runas";
            Process.Start(self);
            return 0;
        }
        try { return RunGui(gui); }
        catch { return 6; }
    }
}
