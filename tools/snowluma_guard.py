"""SnowLuma watchdog and PC temperature/memory guard.

Checks the SnowLuma WebUI/OneBot port, restarts SnowLuma with its bundled
node.exe when it is down, and sends a short notification through AstrBot's
Open API (with optional SMTP fallback). Also alerts when CPU/GPU temperatures
or memory usage stay above the configured thresholds.
"""

from __future__ import annotations

import argparse
import json
import logging
import logging.handlers
import msvcrt
import os
import re
import smtplib
import socket
import ssl
import subprocess
import sys
import time
from email.mime.text import MIMEText
from pathlib import Path
from urllib.parse import urlparse

import psutil
import requests

BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_PATH = BASE_DIR / "tools" / "snowluma_guard.json"
LOG_PATH = Path.home() / "Desktop" / "大肥鱼专用文件夹" / "snowluma_guard.log"
LOCK_PATH = Path.home() / "Desktop" / "大肥鱼专用文件夹" / "snowluma_guard.lock"
RESTART_LOG = BASE_DIR / "SnowLuma" / "logs" / "guardian-restart.log"

DEFAULT_CONFIG = {
    "astrbot": {
        "api": "http://127.0.0.1:6185",
        "token_file": str(BASE_DIR / ".astrbot_token"),
        "umo": "qq_sujinyan:FriendMessage:YOUR_QQ_ID",
    },
    "snowluma": {
        "enabled": True,
        "host": "127.0.0.1",
        "port": 5099,
        "cwd": str(BASE_DIR / "SnowLuma"),
        "node": str(BASE_DIR / "SnowLuma" / "node.exe"),
        "script": "index.mjs",
        "check_seconds": 300,
        "restart_cooldown_seconds": 600,
        "startup_grace_seconds": 30,
        "wait_seconds": 30,
    },
    "system": {
        "enabled": True,
        "check_seconds": 60,
        "lhm_url": "http://127.0.0.1:18085/data.json",
        "cpu_threshold_c": 85,
        "gpu_threshold_c": 85,
        "memory_threshold_percent": 90,
        "sustain_checks": 3,
        "cooldown_seconds": 1800,
    },
    "email": {
        "enabled": False,
        "smtp_host": "",
        "smtp_port": 465,
        "username": "",
        "password": "",
        "to": "",
    },
}


def load_config() -> dict:
    """Load the JSON config, falling back to defaults for missing keys."""
    config = json.loads(json.dumps(DEFAULT_CONFIG))
    if CONFIG_PATH.exists():
        try:
            raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            logging.error("Cannot read config: %s", exc)
            raw = {}
        for section, values in raw.items():
            if isinstance(values, dict) and isinstance(config.get(section), dict):
                config[section].update(values)
            else:
                config[section] = values
    return config


def setup_logging() -> None:
    """Log to stderr and a rotating file."""
    handler = logging.handlers.RotatingFileHandler(
        LOG_PATH, maxBytes=1_048_576, backupCount=2, encoding="utf-8"
    )
    formatter = logging.Formatter("[%(asctime)s] %(levelname)s %(message)s", "%Y-%m-%d %H:%M:%S")
    handler.setFormatter(formatter)
    stream = logging.StreamHandler(sys.stdout)
    stream.setFormatter(formatter)
    logging.basicConfig(level=logging.INFO, handlers=[handler, stream])


def port_open(host: str, port: int, timeout: float = 2.0) -> bool:
    """Return True when a TCP port accepts connections."""
    try:
        with socket.create_connection((host, int(port)), timeout=timeout):
            return True
    except OSError:
        return False


def snowluma_processes() -> list[psutil.Process]:
    """Find node.exe processes running SnowLuma's index.mjs."""
    found: list[psutil.Process] = []
    for proc in psutil.process_iter(["pid", "name", "cmdline"]):
        try:
            if (proc.info.get("name") or "").lower() != "node.exe":
                continue
            cmdline = " ".join(proc.info.get("cmdline") or [])
            if "SnowLuma" in cmdline and "index.mjs" in cmdline:
                found.append(proc)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return found


def read_token(config: dict) -> str:
    """Read the AstrBot dashboard token from disk."""
    token_file = Path(config["astrbot"]["token_file"])
    if not token_file.exists():
        return ""
    return token_file.read_text(encoding="utf-8").strip()


def send_email(config: dict, text: str) -> bool:
    """Send a fallback email if SMTP is configured."""
    email = config.get("email", {})
    if not email.get("enabled"):
        return False
    host = str(email.get("smtp_host") or "")
    username = str(email.get("username") or "")
    password = str(email.get("password") or "")
    to_addr = str(email.get("to") or "")
    if not (host and username and password and to_addr):
        logging.error("Email fallback is enabled but incomplete")
        return False
    message = MIMEText(text, "plain", "utf-8")
    message["Subject"] = "SnowLuma / 苏瑾言 守护提醒"
    message["From"] = username
    message["To"] = to_addr
    try:
        port = int(email.get("smtp_port") or 465)
        if port == 465:
            server = smtplib.SMTP_SSL(host, port, timeout=15, context=ssl.create_default_context())
        else:
            server = smtplib.SMTP(host, port, timeout=15)
            server.starttls(context=ssl.create_default_context())
        with server:
            server.login(username, password)
            server.sendmail(username, [to_addr], message.as_string())
        logging.info("Email notification sent to %s", to_addr)
        return True
    except Exception as exc:
        logging.error("Email notification failed: %s", exc)
        return False


def notify(config: dict, text: str) -> bool:
    """Send a QQ message via AstrBot, falling back to email."""
    api = str(config["astrbot"]["api"]).rstrip("/")
    umo = str(config["astrbot"]["umo"])
    token = read_token(config)
    if token:
        try:
            payload = json.dumps(
                {"umo": umo, "message": text},
                ensure_ascii=False,
            ).encode("utf-8")
            response = requests.post(
                f"{api}/api/v1/im/messages",
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json; charset=utf-8",
                },
                data=payload,
                timeout=10,
            )
            if response.ok:
                logging.info("QQ notification sent: %s", text)
                return True
            logging.warning("QQ notification failed: HTTP %s %s", response.status_code, response.text[:200])
        except requests.RequestException as exc:
            logging.warning("QQ notification failed: %s", exc)
    else:
        logging.warning("AstrBot token missing; cannot send QQ notification")
    return send_email(config, text)


def _to_float(value: object) -> float | None:
    """Extract the first number from a sensor value such as '57.1 °C'."""
    match = re.search(r"-?\d+(?:\.\d+)?", str(value or ""))
    if not match:
        return None
    try:
        return float(match.group(0))
    except ValueError:
        return None


def read_lhm_temps(url: str) -> tuple[float | None, float | None]:
    """Read CPU and GPU core temperatures from LibreHardwareMonitor.

    Args:
        url: LHM remote web server data.json URL.

    Returns:
        (cpu_temp, gpu_temp); either can be None when the sensor is missing.
    """
    response = requests.get(url, timeout=5)
    response.raise_for_status()
    data = response.json()
    cpu_values: list[float] = []
    gpu_values: list[float] = []

    def walk(node: dict, path: str) -> None:
        text = str(node.get("Text") or "")
        value = str(node.get("Value") or "")
        current = f"{path}/{text}" if text else path
        low = current.lower()
        if "°c" in value.lower():
            number = _to_float(value)
            if number is not None:
                if "gpu core" in low and any(
                    key in low for key in ("nvidia", "radeon", "gpu")
                ):
                    gpu_values.append(number)
                elif any(
                    key in low for key in ("ryzen", "intel", "cpu")
                ) and any(
                    key in low
                    for key in ("cpu package", "core (tctl", "tdie", "cpu core")
                ):
                    cpu_values.append(number)
        for child in node.get("Children") or []:
            if isinstance(child, dict):
                walk(child, current)

    walk(data, "")
    cpu = max(cpu_values) if cpu_values else None
    gpu = max(gpu_values) if gpu_values else None
    return cpu, gpu


def read_nvidia_temp() -> float | None:
    """Fallback GPU temperature through nvidia-smi."""
    try:
        output = subprocess.check_output(
            [
                "nvidia-smi",
                "--query-gpu=temperature.gpu",
                "--format=csv,noheader,nounits",
            ],
            text=True,
            timeout=5,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        values = [
            float(line.strip())
            for line in output.splitlines()
            if line.strip().replace(".", "", 1).isdigit()
        ]
        return max(values) if values else None
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def _port_owner_pid(port: int) -> int | None:
    """Return the PID listening on a local port, or None."""
    try:
        for conn in psutil.net_connections(kind="inet"):
            if (
                conn.status == psutil.CONN_LISTEN
                and conn.laddr
                and conn.laddr.port == port
            ):
                return int(conn.pid)
    except (psutil.AccessDenied, psutil.NoSuchProcess, OSError):
        pass
    return None


def _process_private_bytes(proc: psutil.Process) -> int:
    try:
        return int(proc.memory_info().private)
    except (psutil.AccessDenied, psutil.NoSuchProcess, OSError):
        return 0


def _wmi_private_bytes(pid: int) -> int:
    """Read private bytes for another user's process through WMI.

    AstrBot runs as YOUR_SERVICE_USER while this guardian runs as YOUR_USER_NAME, so
    psutil.memory_info() gets AccessDenied. Win32_PerfFormattedData is
    readable across users and gives the same private-byte value.
    """
    try:
        command = (
            "$p = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process "
            f"-Filter 'IDProcess={int(pid)}'; if ($p) {{ $p.PrivateBytes }}"
        )
        output = subprocess.check_output(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
            stderr=subprocess.DEVNULL,
            timeout=10,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        ).decode("utf-8", errors="ignore")
        lines = [line.strip() for line in output.splitlines() if line.strip()]
        return int(float(lines[-1])) if lines else 0
    except (OSError, subprocess.SubprocessError, ValueError):
        return 0


def read_service_memory(config: dict) -> dict:
    """Return AstrBot/Ollama private memory as percent of physical RAM."""
    total = float(psutil.virtual_memory().total)
    threshold = float(config.get("system", {}).get("process_memory_threshold_percent", 80))

    astrbot_bytes = 0
    try:
        port = int(urlparse(str(config.get("astrbot", {}).get("api", ""))).port or 6185)
    except Exception:
        port = 6185
    astrbot_pid = _port_owner_pid(port)
    if astrbot_pid:
        astrbot_bytes = _wmi_private_bytes(astrbot_pid)

    ollama_bytes = 0
    for proc in psutil.process_iter(["pid", "name"]):
        try:
            name = (proc.info.get("name") or "").lower()
            if name in {
                "ollama.exe",
                "llama-server.exe",
                "ollama_llama_server.exe",
            } or name.startswith("llama-server"):
                ollama_bytes += _process_private_bytes(proc)
        except (psutil.AccessDenied, psutil.NoSuchProcess, OSError):
            continue

    astrbot_percent = astrbot_bytes / total * 100 if total else 0
    ollama_percent = ollama_bytes / total * 100 if total else 0
    return {
        "astrbot_memory_percent": astrbot_percent,
        "astrbot_memory_bytes": astrbot_bytes,
        "ollama_memory_percent": ollama_percent,
        "ollama_memory_bytes": ollama_bytes,
        "process_memory_threshold_percent": threshold,
    }


def read_api_token_usage(config: dict) -> int:
    """Read today's external AstrBot token usage from the companion store."""
    path = BASE_DIR / "AstrBot" / "data" / "plugin_data" / "astrbot_plugin_private_companion" / "companions.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        usage = data.get("token_usage") if isinstance(data, dict) else {}
        external = usage.get("external") if isinstance(usage, dict) else {}
        by_day = external.get("by_day") if isinstance(external, dict) else {}
        today = by_day.get(__import__("datetime").date.today().isoformat()) if isinstance(by_day, dict) else {}
        return int((today or {}).get("total_tokens", 0) or 0)
    except (OSError, ValueError, TypeError):
        return 0


def check_system(
    config: dict,
    state: dict,
    *,
    send_alert: bool = True,
) -> dict:
    """Check temperatures and memory, alerting after sustained overload.

    Args:
        config: Full guardian config.
        state: Mutable streak/cooldown state.
        send_alert: Send a QQ/email alert when a threshold is sustained.

    Returns:
        Current values and the alert text, if any.
    """
    system = config.get("system", {})
    if not system.get("enabled", True):
        return {}
    cpu = gpu = None
    try:
        cpu, gpu = read_lhm_temps(str(system["lhm_url"]))
    except Exception as exc:
        now = time.time()
        if now - float(state.get("last_lhm_warn", 0)) > 300:
            logging.warning("LHM sensor read failed: %s", exc)
            state["last_lhm_warn"] = now
    if gpu is None:
        gpu = read_nvidia_temp()
    memory = float(psutil.virtual_memory().percent)
    service_memory = read_service_memory(config)
    service_threshold = float(service_memory.get("process_memory_threshold_percent", 80))
    api_tokens = read_api_token_usage(config)
    api_warn_tokens = int(system.get("api_daily_token_warn", 1000000) or 1000000)
    api_warn_cooldown = int(system.get("api_warn_cooldown_seconds", 86400) or 86400)
    now = time.time()

    metrics = [
        ("cpu", cpu, float(system.get("cpu_threshold_c", 85)), "CPU"),
        ("gpu", gpu, float(system.get("gpu_threshold_c", 85)), "GPU"),
        (
            "memory",
            memory,
            float(system.get("memory_threshold_percent", 90)),
            "内存",
        ),
        (
            "astrbot_memory",
            service_memory.get("astrbot_memory_percent", 0),
            service_threshold,
            "AstrBot 内存",
        ),
        (
            "ollama_memory",
            service_memory.get("ollama_memory_percent", 0),
            service_threshold,
            "Ollama 内存",
        ),
    ]
    alert_parts: list[str] = []
    for key, value, threshold, label in metrics:
        if value is None:
            state[f"{key}_streak"] = 0
            continue
        if value >= threshold:
            state[f"{key}_streak"] = int(state.get(f"{key}_streak", 0)) + 1
        else:
            state[f"{key}_streak"] = 0
        streak = int(state.get(f"{key}_streak", 0))
        if (
            streak >= int(system.get("sustain_checks", 3))
            and now - float(state.get(f"{key}_last_alert", 0))
            >= int(system.get("cooldown_seconds", 1800))
        ):
            state[f"{key}_last_alert"] = now
            state[f"{key}_streak"] = 0
            if key == "memory":
                alert_parts.append(f"内存占用 {value:.0f}%")
            elif key in ("astrbot_memory", "ollama_memory"):
                bytes_key = "astrbot_memory_bytes" if key == "astrbot_memory" else "ollama_memory_bytes"
                size_gb = float(service_memory.get(bytes_key, 0)) / (1024 ** 3)
                alert_parts.append(f"{label} {value:.0f}%（约 {size_gb:.1f}GB）")
            else:
                alert_parts.append(f"{label} {value:.0f}°C")
            logging.warning("System threshold hit: %s %.1f >= %.1f", key, value, threshold)

    alert_text = ""
    api_alert = False
    if (
        api_tokens >= api_warn_tokens
        and now - float(state.get("api_last_alert", 0)) >= api_warn_cooldown
    ):
        state["api_last_alert"] = now
        api_alert = True
        alert_parts.append(f"今日 API 用量约 {api_tokens / 1000000:.1f}M tokens")
        logging.warning("API daily usage warning: %s tokens", api_tokens)
    if alert_parts:
        alert_text = "哥，电脑状态有点不对：" + "，".join(alert_parts) + "。要不要看一下？"
        if api_alert and len(alert_parts) == 1:
            alert_text = (
                "哥，今天的 API 用量已经比较大啦，"
                "如果你接下来要处理大工程，留意一下哦。"
            )
        if send_alert:
            notify(config, alert_text)

    return {
        "cpu": cpu,
        "gpu": gpu,
        "memory": memory,
        "astrbot_memory_percent": service_memory.get("astrbot_memory_percent", 0),
        "astrbot_memory_bytes": service_memory.get("astrbot_memory_bytes", 0),
        "ollama_memory_percent": service_memory.get("ollama_memory_percent", 0),
        "ollama_memory_bytes": service_memory.get("ollama_memory_bytes", 0),
        "api_tokens_today": api_tokens,
        "api_token_warn": api_warn_tokens,
        "alert": alert_text,
    }


def restart_snowluma(config: dict) -> bool:
    """Restart SnowLuma and wait for its port to come back."""
    sl = config["snowluma"]
    cwd = Path(sl["cwd"])
    node = Path(sl["node"])
    script = str(sl["script"])
    if not node.exists():
        logging.error("SnowLuma node.exe not found: %s", node)
        return False
    if not (cwd / script).exists():
        logging.error("SnowLuma script not found: %s", cwd / script)
        return False

    for proc in snowluma_processes():
        try:
            logging.warning("Stopping stale SnowLuma process pid=%s", proc.pid)
            proc.terminate()
            proc.wait(timeout=5)
        except (psutil.NoSuchProcess, psutil.TimeoutExpired):
            try:
                proc.kill()
            except psutil.NoSuchProcess:
                pass
        except psutil.AccessDenied:
            logging.error("Access denied stopping SnowLuma pid=%s", proc.pid)

    RESTART_LOG.parent.mkdir(parents=True, exist_ok=True)
    try:
        with RESTART_LOG.open("ab") as output:
            subprocess.Popen(
                [str(node), script],
                cwd=str(cwd),
                stdout=output,
                stderr=subprocess.STDOUT,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
    except OSError as exc:
        logging.error("SnowLuma start failed: %s", exc)
        return False

    deadline = time.time() + int(sl["wait_seconds"])
    while time.time() < deadline:
        if port_open(str(sl["host"]), int(sl["port"])):
            logging.info("SnowLuma restarted and port %s is open", sl["port"])
            return True
        time.sleep(2)
    logging.error("SnowLuma restarted but port %s did not open in time", sl["port"])
    return False


def _read_inbound_log_times() -> tuple[float | None, float | None]:
    """Return (last [Event] private timestamp, last message-push timestamp)."""
    import datetime as _dt
    log_dir = BASE_DIR / "SnowLuma" / "logs"
    files = sorted(log_dir.glob("snowluma-*.log"))[-2:]
    last_event = None
    last_push = None
    for path in files:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[-4000:]
        except OSError:
            continue
        day = path.stem.replace("snowluma-", "")
        try:
            date = _dt.date.fromisoformat(day)
        except ValueError:
            continue
        for line in lines:
            m = re.match(r"^(\d{2}:\d{2}:\d{2})\s", line)
            if not m:
                continue
            try:
                ts = _dt.datetime.combine(date, _dt.time.fromisoformat(m.group(1))).timestamp()
            except ValueError:
                continue
            if "[Event] 私聊" in line:
                last_event = ts
            if "MsgPush" in line or "Event0x210" in line:
                last_push = ts
    return last_event, last_push


def inbound_hook_fake_dead(config: dict) -> bool:
    """Detect inbound packets that did not become an [Event] within 5 minutes."""
    last_event, last_push = _read_inbound_log_times()
    if last_push is None:
        return False
    if last_event is not None and last_event >= last_push:
        return False
    return time.time() - last_push >= 300


def check_snowluma(config: dict, restart: bool = True) -> bool:
    """Check SnowLuma and optionally restart it. Returns True when healthy."""
    sl = config["snowluma"]
    if not sl.get("enabled", True):
        return True
    host = str(sl["host"])
    port = int(sl["port"])
    healthy = port_open(host, port)
    procs = snowluma_processes()
    if healthy:
        logging.info("SnowLuma OK (port %s open, %s process(es))", port, len(procs))
        return True

    logging.warning("SnowLuma DOWN (port %s closed, %s process(es))", port, len(procs))
    if not restart:
        return False
    restarted = restart_snowluma(config)
    if restarted:
        notify(config, "哥，SnowLuma 刚才掉线了，瑾言已经把它重新启动好了。")
    else:
        notify(config, "哥，SnowLuma 掉线了，瑾言尝试重启但没有起来，你有空看一下 logs。")
    return restarted


class SingleInstance:
    """Keep only one guardian process alive on Windows."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.handle = None

    def __enter__(self) -> "SingleInstance":
        self.handle = self.path.open("a+")
        self.handle.seek(0)
        try:
            msvcrt.locking(self.handle.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise SystemExit("Another snowluma_guard.py is already running")
        self.handle.seek(0)
        self.handle.truncate()
        self.handle.write(str(os.getpid()))
        self.handle.flush()
        return self

    def __exit__(self, *_args) -> None:
        if self.handle:
            try:
                self.handle.seek(0)
                msvcrt.locking(self.handle.fileno(), msvcrt.LK_UNLCK, 1)
            except OSError:
                pass
            self.handle.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="SnowLuma and system guardian")
    parser.add_argument("--check", action="store_true", help="check SnowLuma once without restarting")
    parser.add_argument("--once", action="store_true", help="check SnowLuma once and restart if needed")
    parser.add_argument("--check-system", action="store_true", help="print CPU/GPU/memory once")
    args = parser.parse_args()

    setup_logging()
    config = load_config()
    if args.check:
        return 0 if check_snowluma(config, restart=False) else 1
    if args.once:
        return 0 if check_snowluma(config, restart=True) else 1
    if args.check_system:
        result = check_system(config, {}, send_alert=False)
        print(json.dumps(result, ensure_ascii=True, indent=2))
        return 0

    with SingleInstance(LOCK_PATH):
        logging.info("SnowLuma + system guardian started")
        grace = int(config["snowluma"].get("startup_grace_seconds", 30))
        if grace > 0:
            time.sleep(grace)
        snow_interval = int(config["snowluma"].get("check_seconds", 300))
        system_interval = int(config.get("system", {}).get("check_seconds", 60))
        last_snow = 0.0
        last_system = 0.0
        last_restart = 0.0
        system_state: dict = {}
        while True:
            now = time.time()
            if now - last_snow >= snow_interval:
                last_snow = now
                try:
                    healthy = port_open(
                        str(config["snowluma"]["host"]),
                        int(config["snowluma"]["port"]),
                    )
                    if not healthy:
                        cooldown = int(
                            config["snowluma"].get("restart_cooldown_seconds", 600)
                        )
                        if now - last_restart >= cooldown:
                            logging.warning("SnowLuma is down; attempting restart")
                            if restart_snowluma(config):
                                last_restart = now
                                notify(
                                    config,
                                    "哥，SnowLuma 刚才掉线了，瑾言已经把它重新启动好了。",
                                )
                            else:
                                last_restart = now
                                notify(
                                    config,
                                    "哥，SnowLuma 掉线了，瑾言尝试重启但没有起来，你有空看一下 logs。",
                                )
                    else:
                        logging.info("SnowLuma OK (port %s)", config["snowluma"]["port"])
                        if inbound_hook_fake_dead(config):
                            now2 = time.time()
                            if now2 - last_restart >= int(config["snowluma"].get("restart_cooldown_seconds", 600)):
                                logging.warning("SnowLuma inbound hook appears fake-dead; restarting")
                                if restart_snowluma(config):
                                    last_restart = now2
                                    notify(config, "哥，SnowLuma 入站 Hook 疑似假死，瑾言已经重启了一次。")
                except Exception:
                    logging.exception("SnowLuma check failed")

            if (
                config.get("system", {}).get("enabled", True)
                and now - last_system >= system_interval
            ):
                last_system = now
                try:
                    result = check_system(config, system_state)
                    if result.get("alert"):
                        logging.warning("System alert sent: %s", result["alert"])
                except Exception:
                    logging.exception("System check failed")

            time.sleep(30)


if __name__ == "__main__":
    raise SystemExit(main())
