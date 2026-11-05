using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;

namespace CyberButler
{
    public sealed class AgentRuntimeService : ServiceBase
    {
        private Process child;
        private IntPtr job = IntPtr.Zero;
        private readonly object gate = new object();
        private string logPath;

        public AgentRuntimeService()
        {
            ServiceName = "CyberButlerAgentRuntime";
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

            string python = Path.GetFullPath(Path.Combine(root, @"AgentRuntime\.venv\Scripts\python.exe"));
            string workdir = Path.GetFullPath(Path.Combine(root, "AgentRuntime"));
            string dataDir = Path.GetFullPath(Path.Combine(workdir, "data"));
            logPath = Path.GetFullPath(Path.Combine(dataDir, @"logs\service-AgentRuntime.log"));

            if (!File.Exists(python)) { throw new FileNotFoundException("AgentRuntime python not found", python); }
            if (!Directory.Exists(workdir)) { throw new DirectoryNotFoundException("AgentRuntime root not found: " + workdir); }
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
                CreateNoWindow = true
            };
            psi.EnvironmentVariables["AgentRuntime_SERVICE_MODE"] = "1";
            psi.EnvironmentVariables["AgentRuntime_ROOT"] = workdir;
            psi.EnvironmentVariables["AgentRuntime_DISABLE_GUI"] = "1";
            psi.EnvironmentVariables["NO_GUI"] = "1";
            psi.EnvironmentVariables["PYTHONUTF8"] = "1";
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            psi.EnvironmentVariables["PYTHONUNBUFFERED"] = "1";
            psi.EnvironmentVariables["MPLBACKEND"] = "Agg";
            psi.EnvironmentVariables["QT_QPA_PLATFORM"] = "offscreen";
            psi.EnvironmentVariables["DISPLAY"] = "";

            // Prove the service account can write the data directory before
            // launching AgentRuntime; a failure is logged and fails the service.
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

            child = StartSuspended(psi);
            child.EnableRaisingEvents = true;
            child.Exited += ChildExited;
            if (!AssignProcessToJobObject(job, child.Handle))
            {
                int err = Marshal.GetLastWin32Error();
                try { child.Kill(); } catch { }
                throw new InvalidOperationException("AssignProcessToJobObject failed: " + err);
            }
            ResumeSuspendedChild();
            Append("SERVICE_CHILD pid=" + child.Id + " job=assigned suspended-start=true");
        }

        private IntPtr suspendedThread = IntPtr.Zero;

        private Process StartSuspended(ProcessStartInfo psi)
        {
            StringBuilder env = new StringBuilder();
            foreach (System.Collections.DictionaryEntry item in psi.EnvironmentVariables)
            {
                env.Append((string)item.Key).Append('=').Append((string)item.Value).Append('\0');
            }
            env.Append('\0');
            STARTUPINFO si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            PROCESS_INFORMATION pi;
            StringBuilder command = new StringBuilder("\"" + psi.FileName + "\" " + psi.Arguments);
            const uint CREATE_SUSPENDED = 0x00000004;
            const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
            const uint CREATE_NO_WINDOW = 0x08000000;
            if (!CreateProcessW(null, command, IntPtr.Zero, IntPtr.Zero, false,
                CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                env, psi.WorkingDirectory, ref si, out pi))
            {
                throw new InvalidOperationException("CreateProcess suspended failed: " + Marshal.GetLastWin32Error());
            }
            suspendedThread = pi.hThread;
            CloseHandle(pi.hProcess);
            return Process.GetProcessById(pi.dwProcessId);
        }

        private void ResumeSuspendedChild()
        {
            if (suspendedThread == IntPtr.Zero) { return; }
            try
            {
                if (ResumeThread(suspendedThread) == uint.MaxValue)
                {
                    throw new InvalidOperationException("ResumeThread failed: " + Marshal.GetLastWin32Error());
                }
            }
            finally
            {
                CloseHandle(suspendedThread);
                suspendedThread = IntPtr.Zero;
            }
        }

        private void ChildExited(object sender, EventArgs e)
        {
            int code = -1;
            try { code = child != null ? child.ExitCode : -1; } catch { }
            Append("SERVICE_CHILD_EXIT code=" + code);
            // A dead child must be visible to SCM and restarted by its failure
            // policy; do not leave the service reporting Running with no child.
            try { Stop(); } catch (Exception ex) { Append("SERVICE_STOP_FAIL " + ex.GetType().Name); }
        }

        private void Append(string line)
        {
            if (line == null) { return; }
            try
            {
                lock (typeof(AgentRuntimeService))
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
            ServiceBase.Run(new AgentRuntimeService());
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

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO
        {
            public int cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public int dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool CreateProcessW(string applicationName, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint creationFlags,
            StringBuilder environment, string currentDirectory, ref STARTUPINFO startupInfo,
            out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);
}
