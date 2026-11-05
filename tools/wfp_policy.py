"""Validation for the v1.6.2 WFP policy document.

The policy is deliberately small: a service SID, explicit domains/IPs, and an
audit/enforce mode. Resolution and filter installation live in wfp_guard.py.
"""

from __future__ import annotations

import json
import socket
from pathlib import Path

MODES = {"audit", "enforce"}


class PolicyError(ValueError):
    """PolicyError helper/type."""
    pass


def _port(value, field: str) -> int:
    """Port.
    
    Args:
        value: caller-supplied value.
        field: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        port = int(value)
    except (TypeError, ValueError) as exc:
        raise PolicyError(f"{field} must be an integer") from exc
    if not 1 <= port <= 65535:
        raise PolicyError(f"{field} out of range")
    return port


def validate(policy: dict) -> dict:
    """Validate.
    
    Args:
        policy: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if not isinstance(policy, dict):
        raise PolicyError("policy must be an object")
    if policy.get("schema") != 1:
        raise PolicyError("unsupported policy schema")
    mode = str(policy.get("mode", "")).lower()
    if mode not in MODES:
        raise PolicyError("mode must be audit or enforce")
    account = str(policy.get("service_account", "")).strip()
    if not account:
        raise PolicyError("service_account is required")
    allow = policy.get("allow", [])
    if not isinstance(allow, list):
        raise PolicyError("allow must be a list")
    canonical_allow = []
    for entry in allow:
        if not isinstance(entry, dict):
            raise PolicyError("allow entries must be objects")
        kind = str(entry.get("kind", "")).lower()
        if kind == "loopback":
            canonical_allow.append({"kind": "loopback", "port": _port(entry.get("port"), "allow.port")})
        elif kind == "domain":
            name = str(entry.get("name", "")).strip().lower()
            if not name or "://" in name or "/" in name:
                raise PolicyError("invalid domain name")
            canonical_allow.append({"kind": "domain", "name": name, "port": _port(entry.get("port", 443), "allow.port")})
        else:
            raise PolicyError("allow kind must be loopback or domain")
    return {
        "schema": 1,
        "mode": mode,
        "service_account": account,
        "allow": canonical_allow,
        "block_unknown": bool(policy.get("block_unknown", True)),
    }


def load(path: Path) -> dict:
    """Load.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return validate(json.loads(Path(path).read_text(encoding="utf-8")))


def resolve_domains(policy: dict) -> list[dict]:
    """Resolve domains.
    
    Args:
        policy: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    resolved = []
    for entry in validate(policy)["allow"]:
        if entry["kind"] != "domain":
            continue
        try:
            infos = socket.getaddrinfo(entry["name"], entry["port"], type=socket.SOCK_STREAM)
        except socket.gaierror:
            continue
        ips = sorted({info[4][0] for info in infos})
        resolved.append({"name": entry["name"], "port": entry["port"], "ips": ips})
    return resolved
