"""WFP-backed outbound enforcement using Windows Firewall per-user rules.

Windows Defender Firewall is a WFP policy provider. We express a default-deny
IPv4 egress policy as block rules for the *complement* of the allowed address
set. This avoids the block-overrides-allow problem of adding a single block-all
rule plus allow exceptions.

The guard runs as SYSTEM in its own scheduled task. It never runs inside the
Agent process and never kills or freezes a process on an alert.
"""

from __future__ import annotations

import ipaddress
import os
import socket
import subprocess
from dataclasses import dataclass
from pathlib import Path

from wfp_policy import PolicyError, resolve_domains, validate

RULE_PREFIX = "CBS-Agent-Egress"


class WfpError(RuntimeError):
    pass


@dataclass(frozen=True)
class BlockPlan:
    allowed: tuple[str, ...]
    blocked: tuple[str, ...]


def _ipv4(value: str) -> ipaddress.IPv4Network | None:
    try:
        return ipaddress.ip_network(value, strict=False)
    except ValueError:
        return None


def build_block_plan(policy: dict, *, resolve: bool = True) -> BlockPlan:
    """Return IPv4 allow/block sets; loopback is always permitted."""
    canonical = validate(policy)
    allowed: list[ipaddress.IPv4Network] = [ipaddress.ip_network("127.0.0.0/8")]
    if resolve:
        for entry in resolve_domains(canonical):
            for ip in entry["ips"]:
                network = _ipv4(str(ip))
                if network is not None:
                    allowed.append(network)
    allowed = list(ipaddress.collapse_addresses(allowed))
    # Compute 0.0.0.0/0 minus allowed without materialising 4 billion hosts.
    universe = [ipaddress.ip_network("0.0.0.0/0")]
    for permit in allowed:
        next_universe = []
        for network in universe:
            if network.subnet_of(permit):
                continue
            if permit.subnet_of(network):
                next_universe.extend(network.address_exclude(permit))
            else:
                next_universe.append(network)
        universe = next_universe
    blocked = universe
    return BlockPlan(
        allowed=tuple(str(item) for item in allowed),
        blocked=tuple(str(item) for item in blocked),
    )


def _sid(account: str) -> str:
    if os.name != "nt":
        return "S-1-5-18"
    command = [
        "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-Command",
        f"$u=Get-LocalUser -Name '{account.replace(chr(39), chr(39)*2)}' -ErrorAction Stop; $u.Sid.Value",
    ]
    result = _run(command)
    sid = (result.stdout or "").strip().splitlines()[-1].strip()
    if not sid.startswith("S-1-"):
        raise WfpError(f"cannot resolve SID for {account}")
    return sid


def _run(command: list[str]) -> subprocess.CompletedProcess:
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    return subprocess.run(command, capture_output=True, text=True, timeout=30, creationflags=flags)


def build_apply_commands(policy: dict, sid: str, mode: str | None = None) -> list[str]:
    canonical = validate(policy)
    effective_mode = (mode or canonical["mode"]).lower()
    if effective_mode == "audit":
        return []
    plan = build_block_plan(canonical)
    if not plan.blocked:
        return []
    # Split long address lists into bounded commands.
    commands: list[str] = []
    chunk: list[str] = []
    for network in plan.blocked:
        chunk.append(str(network))
        if len(chunk) >= 200:
            commands.append(_rule_command(sid, chunk))
            chunk = []
    if chunk:
        commands.append(_rule_command(sid, chunk))
    return commands


def _rule_command(sid: str, networks: list[str]) -> str:
    addresses = ",".join(networks)
    name = RULE_PREFIX + "-" + str(abs(hash(addresses)))[:12]
    return (
        "New-NetFirewallRule "
        f"-DisplayName '{name}' -Name '{name}' "
        f"-LocalUser '{sid}' -Direction Outbound -Action Block "
        f"-RemoteAddress '{addresses}' -Profile Any -Enabled True"
    )


def remove_policy() -> None:
    if os.name != "nt":
        return
    result = _run([
        "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-Command",
        "Get-NetFirewallRule -DisplayName 'CBS-Agent-Egress*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue",
    ])
    if result.returncode != 0:
        raise WfpError((result.stderr or result.stdout or "Remove-NetFirewallRule failed").strip())


def apply_policy(policy: dict, *, allow_enforce: bool = False) -> dict:
    """Apply the policy through Windows Firewall; audit is the safe default.

    A policy that says ``enforce`` is still downgraded to audit unless the
    caller explicitly passes ``allow_enforce`` after real-machine validation.
    """
    canonical = validate(policy)
    effective_mode = canonical["mode"]
    if effective_mode == "enforce" and not allow_enforce and os.environ.get("CBS_WFP_ALLOW_ENFORCE") != "1":
        effective_mode = "audit"
    sid = _sid(canonical["service_account"])
    remove_policy()
    commands = build_apply_commands(canonical, sid, mode=effective_mode)
    if not commands:
        return {"mode": effective_mode, "applied": 0, "sid": sid}
    for command in commands:
        result = _run([
            "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-Command", command,
        ])
        if result.returncode != 0:
            raise WfpError((result.stderr or result.stdout or "New-NetFirewallRule failed").strip())
    return {"mode": effective_mode, "applied": len(commands), "sid": sid}


def _write_status(policy_path: Path, status: dict) -> None:
    target = policy_path.with_name("wfp-guard-status.json")
    tmp = target.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(status, sort_keys=True), encoding="utf-8")
    tmp.replace(target)


def watch(policy_path: Path, interval: int = 15, *, allow_enforce: bool = False) -> None:
    import time

    last_mtime = None
    while True:
        try:
            mtime = policy_path.stat().st_mtime_ns
            if last_mtime != mtime:
                result = apply_policy(
                    json.loads(policy_path.read_text(encoding="utf-8-sig")),
                    allow_enforce=allow_enforce,
                )
                status = {"ok": True, "updated_at": __import__("time").time(), **result}
                _write_status(policy_path, status)
                last_mtime = mtime
        except Exception as exc:
            try:
                _write_status(policy_path, {"ok": False, "error": str(exc), "updated_at": __import__("time").time()})
            except OSError as status_exc:
                print(f"WFP status write failed: {status_exc}", flush=True)
            print(f"WFP policy apply failed: {exc}", flush=True)
        time.sleep(max(2, int(interval)))


if __name__ == "__main__":
    import argparse
    import json

    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", required=True)
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--interval", type=int, default=15)
    parser.add_argument("--allow-enforce", action="store_true")
    args = parser.parse_args()
    data = json.loads(Path(args.policy).read_text(encoding="utf-8-sig"))
    if args.plan:
        print(json.dumps(build_block_plan(data).__dict__, indent=2))
    elif args.watch:
        watch(Path(args.policy), args.interval, allow_enforce=args.allow_enforce)
    else:
        print(json.dumps(apply_policy(data), indent=2))
