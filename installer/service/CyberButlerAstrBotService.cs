using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.ServiceProcess;

namespace CyberButler
{
    public sealed class AstrBotService : ServiceBase
    {
        private Process child;
        private IntPtr job = IntPtr.Zero;
        private readonly object gate = new object();
        private string logPath;

        public AstrBotService()
        {
            ServiceName = "CyberButlerAstrBot";
            CanStop = true;
            CanShutdown = true;
            AutoLog = true;
        }

        protected override void OnStart(string[] args)
        {
            string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            if (root.EndsWith("service", StringComparison.OrdinalIgnoreCase))
            {
                root = Directory.GetParent(root).Parent.FullName;
            }

            string python = Path.GetFullPath(Path.Combine(root, @"AstrBot\.venv\Scripts\python.exe"));
            string workdir = Path.GetFullPath(Path.Combine(root, "AstrBot"));
            string dataDir = Path.GetFullPath(Path.Combine(workdir, "data"));
            logPath = Path.GetFullPath(Path.Combine(dataDir, @"logs\service-astrbot.log"));

            if (!File.Exists(python)) { throw new FileNotFoundException("AstrBot python not found", python); }
            if (!Directory.Exists(workdir)) { throw new DirectoryNotFoundException("AstrBot root not found: " + workdir); }
            Directory.CreateDirectory(Path.GetDirectoryName(logPath));

            Append("SERVICE_START account=" + WindowsIdentity.GetCurrent().Name +
                   " cwd=" + Environment.CurrentDirectory +
                   " workdir=" + workdir +
                   " root=" + root);

            // Session 0 / non-interactive fail-closed environment.
            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = python,
                Arguments = "main.py",
                WorkingDirectory = workdir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            psi.EnvironmentVariables["ASTRBOT_SERVICE_MODE"] = "1";
            psi.EnvironmentVariables["ASTRBOT_ROOT"] = root;
            psi.EnvironmentVariables["ASTRBOT_DISABLE_GUI"] = "1";
            psi.EnvironmentVariables["NO_GUI"] = "1";
            psi.EnvironmentVariables["PYTHONUTF8"] = "1";
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            psi.EnvironmentVariables["PYTHONUNBUFFERED"] = "1";
            psi.EnvironmentVariables["MPLBACKEND"] = "Agg";
            psi.EnvironmentVariables["QT_QPA_PLATFORM"] = "offscreen";
            psi.EnvironmentVariables["DISPLAY"] = "";

            // Prove the service account can write the data directory before
            // launching AstrBot; a failure is logged and fails the service.
            try
            {
                string probe = Path.Combine(dataDir, ".service-write-probe");
                File.WriteAllText(probe, DateTime.UtcNow.ToString("o"));
                File.Delete(probe);
                Append("SERVICE_DATA_WRITE_OK dir=" + dataDir);
            }
            catch (Exception ex)
            {
                Append("SERVICE_DATA_WRITE_FAIL dir=" + dataDir + " error=" + ex.GetType().Name + ": " + ex.Message);
                throw;
            }

            // Create the job before the child so descendants are bound to it.
            job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) { throw new InvalidOperationException("CreateJobObject failed"); }
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            limits.BasicLimitInformation.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
            if (!SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION))))
            {
                throw new InvalidOperationException("SetInformationJobObject failed: " + Marshal.GetLastWin32Error());
            }

            child = new Process { StartInfo = psi, EnableRaisingEvents = true };
            child.OutputDataReceived += (s, e) => Append(e.Data);
            child.ErrorDataReceived += (s, e) => Append(e.Data);
            child.Start();
            if (!AssignProcessToJobObject(job, child.Handle))
            {
                int err = Marshal.GetLastWin32Error();
                try { child.Kill(); } catch { }
                throw new InvalidOperationException("AssignProcessToJobObject failed: " + err);
            }
            child.BeginOutputReadLine();
            child.BeginErrorReadLine();
            Append("SERVICE_CHILD pid=" + child.Id + " job=assigned");
        }

        private void Append(string line)
        {
            if (line == null) { return; }
            try
            {
                lock (typeof(AstrBotService))
                {
                    File.AppendAllText(logPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + line + Environment.NewLine);
                }
            }
            catch { }
        }

        protected override void OnStop()
        {
            StopChild();
        }

        protected override void OnShutdown()
        {
            StopChild();
            base.OnShutdown();
        }

        private void StopChild()
        {
            lock (gate)
            {
                try
                {
                    if (child != null && !child.HasExited)
                    {
                        try { child.Kill(); child.WaitForExit(10000); } catch { }
                    }
                }
                finally
                {
                    if (job != IntPtr.Zero)
                    {
                        // Closing the job handle kills any remaining descendants.
                        CloseHandle(job);
                        job = IntPtr.Zero;
                    }
                    if (child != null)
                    {
                        try { child.Dispose(); } catch { }
                        child = null;
                    }
                }
            }
        }

        public static void Main()
        {
            ServiceBase.Run(new AstrBotService());
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, uint length);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);
    }
}
