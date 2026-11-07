"""Native Windows service wrapper for the CBS broker.

The service runs the portable Python interpreter and reports SCM state
explicitly. It never relies on cmd.exe, a batch file, or the host PATH.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

try:
    import servicemanager
    import win32event
    import win32service
    import win32serviceutil
except ImportError as exc:  # pragma: no cover - exercised by invalid installs
    raise SystemExit("pywin32 is required for the CBS broker service: " + str(exc))


class CBSBrokerService(win32serviceutil.ServiceFramework):
    """Native SCM service that owns the broker child process."""

    _svc_name_ = "Cyber-Butler Broker"
    _svc_display_name_ = "Cyber-Butler Broker"
    _svc_description_ = "Cyber-Butler broker, running under the bundled Python 3.13 runtime."

    def __init__(self, args):
        """Create the service stop event."""
        super().__init__(args)
        self.stop_event = win32event.CreateEvent(None, 0, 0, None)
        self.process = None
        self.log_path = None

    def _root(self) -> Path:
        """Return the install root containing tools/ and python/."""
        return Path(__file__).resolve().parents[1]

    def _log(self, message: str) -> None:
        """Append a service diagnostic line to broker-crash.log."""
        try:
            path = self._root() / "broker-crash.log"
            with path.open("a", encoding="utf-8") as handle:
                handle.write(message.rstrip() + "\n")
        except OSError:
            pass

    def SvcStop(self):
        """Ask the broker child to stop and report STOP_PENDING."""
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        win32event.SetEvent(self.stop_event)
        if self.process is not None and self.process.poll() is None:
            try:
                self.process.terminate()
                self.process.wait(timeout=15)
            except Exception as exc:
                self._log("SERVICE_STOP terminate failed: " + repr(exc))
                try:
                    self.process.kill()
                except Exception:
                    pass

    def SvcDoRun(self):
        """Start broker.py, report SERVICE_RUNNING, and wait for stop."""
        self.ReportServiceStatus(win32service.SERVICE_START_PENDING)
        root = self._root()
        python = root / "python" / "python.exe"
        broker = root / "tools" / "broker.py"
        log = root / "broker-crash.log"
        self.log_path = log
        self._log("SERVICE_START root=" + str(root) + " python=" + str(python))
        if not python.is_file():
            self._log("SERVICE_FATAL portable python missing: " + str(python))
            raise RuntimeError("portable python missing: " + str(python))
        if not broker.is_file():
            self._log("SERVICE_FATAL broker.py missing: " + str(broker))
            raise RuntimeError("broker.py missing: " + str(broker))
        env = os.environ.copy()
        env["PYTHONPATH"] = os.pathsep.join([str(root), str(root / "tools"), str(root / "python" / "Lib" / "site-packages")])
        env["PYTHONUTF8"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONUNBUFFERED"] = "1"
        try:
            with log.open("ab") as output:
                self.process = subprocess.Popen(
                    [str(python), str(broker)],
                    cwd=str(root),
                    env=env,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                )
                self.ReportServiceStatus(win32service.SERVICE_RUNNING)
                self._log("SERVICE_RUNNING child_pid=" + str(self.process.pid))
                while self.process.poll() is None:
                    result = win32event.WaitForSingleObject(self.stop_event, 1000)
                    if result == win32event.WAIT_OBJECT_0:
                        break
                code = self.process.poll()
                self._log("SERVICE_CHILD_EXIT code=" + str(code))
        except Exception as exc:
            self._log("SERVICE_FATAL " + repr(exc))
            raise
        finally:
            self.ReportServiceStatus(win32service.SERVICE_STOPPED)


if __name__ == "__main__":
    win32serviceutil.HandleCommandLine(CBSBrokerService)
