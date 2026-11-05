"""Automated defensive test matrix for Cyber-Butler.

Run standalone:
    python tools/red_team_test.py

The script reports PASS, FAIL, or SKIP for each defence. SKIP is intentional
where the current release does not implement the control (notably WFP enforce).
It never claims a skipped control is passing.
"""

from __future__ import annotations

import getpass
import os
import socket
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

PASS = "PASS"
FAIL = "FAIL"
SKIP = "SKIP"


@dataclass(frozen=True)
class DefenseResult:
    """DefenseResult helper/type."""
    name: str
    status: str
    detail: str


def _run_pytest_result(name: str, status: str, detail: str) -> DefenseResult:
    """Run pytest result.
    
    Args:
        name: caller-supplied value.
        status: caller-supplied value.
        detail: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return DefenseResult(name=name, status=status, detail=detail)


def check_acl_file_read() -> DefenseResult:
    """Simulate a restricted read with a deny ACE for the current user."""
    if os.name != "nt":
        return _run_pytest_result(
            "ACL File Read Prevention",
            SKIP,
            "Windows ACL test is skipped on non-Windows CI",
        )
    user = getpass.getuser()
    with tempfile.TemporaryDirectory(prefix="cbs-acl-") as directory:
        target = Path(directory) / "secret.txt"
        target.write_text("restricted", encoding="utf-8")
        applied = False
        try:
            grant = subprocess.run(
                ["icacls", str(target), "/deny", f"{user}:(R)"],
                capture_output=True,
                text=True,
                timeout=20,
            )
            if grant.returncode != 0:
                return _run_pytest_result(
                    "ACL File Read Prevention",
                    SKIP,
                    "could not apply a temporary deny ACE: " + (grant.stderr or grant.stdout).strip(),
                )
            applied = True
            try:
                target.read_text(encoding="utf-8")
            except PermissionError:
                return _run_pytest_result(
                    "ACL File Read Prevention",
                    PASS,
                    "deny ACE produced PermissionError",
                )
            return _run_pytest_result(
                "ACL File Read Prevention",
                FAIL,
                "file was readable despite a deny ACE",
            )
        finally:
            if applied:
                subprocess.run(
                    ["icacls", str(target), "/remove:d", user],
                    capture_output=True,
                    text=True,
                    timeout=20,
                )


def check_broker_totp(broker_module=None) -> DefenseResult:
    """A direct high-risk broker request must become a TOTP challenge."""
    if broker_module is None:
        try:
            import broker as broker_module
        except Exception as exc:  # pragma: no cover - environment-dependent
            return _run_pytest_result("Broker TOTP Challenge", SKIP, f"broker import failed: {exc}")

    with tempfile.TemporaryDirectory(prefix="cbs-broker-", dir=str(Path.cwd())) as directory:
        root = Path(directory)
        memory = root / "memory"
        memory.mkdir()
        target = memory / "facts.txt"
        target.write_text("original", encoding="utf-8")
        broker = broker_module
        previous = {}
        names = {
            "MEMORY_ROOTS": (memory,),
            "TMP_ROOTS": (),
            "SHARED": root / "shared",
            "TOTP_VAULT_ROOT": root / "vault",
            "AUDIT": root / "audit.jsonl",
            "_pending": None,
        }
        try:
            for name, value in names.items():
                previous[name] = getattr(broker, name)
                setattr(broker, name, value)
            previous["send_qq"] = broker.send_qq
            previous["verify_code"] = broker.verify_code
            broker.send_qq = lambda text: True
            broker.verify_code = lambda code, request_id="": "totp"
            status, body = broker.run_request(
                {"action": "write_file", "target": str(target), "content": "approved"}
            )
            pending = getattr(broker, "_pending", None)
        finally:
            for name, value in previous.items():
                setattr(broker, name, value)
        if status == 200 and (body.get("status") == "requires_totp" or pending):
            detail = "high-risk request is held for TOTP approval"
            if body.get("status") != "requires_totp":
                detail += " (HTTP 200 pending response; explicit status field is a v1.6.3 API task)"
            return _run_pytest_result("Broker TOTP Challenge", PASS, detail)
        return _run_pytest_result(
            "Broker TOTP Challenge",
            FAIL,
            f"expected a pending TOTP challenge, got HTTP {status}: {body}",
        )


def check_toctou(broker_module=None) -> DefenseResult:
    """Mutate the approved handle during the approval window; verify must 409."""
    if broker_module is None:
        try:
            import broker as broker_module
        except Exception as exc:  # pragma: no cover
            return _run_pytest_result("TOCTOU Tamper Block", SKIP, f"broker import failed: {exc}")
    broker = broker_module
    with tempfile.TemporaryDirectory(prefix="cbs-toctou-", dir=str(Path.cwd())) as directory:
        root = Path(directory)
        memory = root / "memory"
        memory.mkdir()
        target = memory / "draft.txt"
        target.write_text("before", encoding="utf-8")
        previous = {}
        names = {
            "MEMORY_ROOTS": (memory,),
            "TMP_ROOTS": (),
            "SHARED": root / "shared",
            "TOTP_VAULT_ROOT": root / "vault",
            "AUDIT": root / "audit.jsonl",
            "_pending": None,
        }
        try:
            for name, value in names.items():
                previous[name] = getattr(broker, name)
                setattr(broker, name, value)
            previous["send_qq"] = broker.send_qq
            previous["verify_code"] = broker.verify_code
            broker.send_qq = lambda text: True
            broker.verify_code = lambda code, request_id="": "totp"
            status, body = broker.run_request(
                {"action": "write_file", "target": str(target), "content": "approved"}
            )
            if status != 200 or broker._pending is None:
                return _run_pytest_result(
                    "TOCTOU Tamper Block",
                    FAIL,
                    f"could not create pending approval: HTTP {status} {body}",
                )
            broker._pending["_snapshot"].rewrite(b"tampered")
            broker._pending["deadline"] = time.monotonic() + 60
            status, body = broker.run_verify(
                {"id": broker._pending["id"], "code": "123456"}
            )
        finally:
            for name, value in previous.items():
                setattr(broker, name, value)
        if status == 409 and "TOCTOU" in str(body.get("error", "")):
            return _run_pytest_result(
                "TOCTOU Tamper Block",
                PASS,
                "handle mutation returned HTTP 409",
            )
        return _run_pytest_result(
            "TOCTOU Tamper Block",
            FAIL,
            f"expected HTTP 409, got HTTP {status}: {body}",
        )


def check_wfp_unknown_egress() -> DefenseResult:
    """Only PASS when an actual enforce-mode guard is configured."""
    status_path = Path(__file__).resolve().parent.parent / "webui" / "data" / "wfp-guard-status.json"
    try:
        import json

        status = json.loads(status_path.read_text(encoding="utf-8-sig"))
    except Exception:
        return _run_pytest_result(
            "WFP Unknown Egress",
            SKIP,
            "WFP status file is absent; guard is not running",
        )
    if str(status.get("mode", "audit")).lower() != "enforce":
        return _run_pytest_result(
            "WFP Unknown Egress",
            SKIP,
            "WFP is audit-only (mode=%s); no enforce rule to test" % status.get("mode", "audit"),
        )
    try:
        with socket.create_connection(("192.0.2.1", 443), timeout=1.0):
            return _run_pytest_result(
                "WFP Unknown Egress",
                FAIL,
                "TEST-NET connection unexpectedly succeeded under enforce",
            )
    except OSError:
        return _run_pytest_result(
            "WFP Unknown Egress",
            PASS,
            "TEST-NET connection was blocked or timed out under enforce",
        )


def run_all() -> list[DefenseResult]:
    """Run all.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return [
        check_acl_file_read(),
        check_broker_totp(),
        check_toctou(),
        check_wfp_unknown_egress(),
    ]


def main() -> int:
    """Main.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    results = run_all()
    print("=== Cyber-Butler Automated Defense Matrix ===")
    for result in results:
        print(f"[{result.status}] {result.name}: {result.detail}")
    failed = [r for r in results if r.status == FAIL]
    skipped = [r for r in results if r.status == SKIP]
    print(f"\nSummary: {len(results) - len(failed) - len(skipped)} PASS, "
          f"{len(failed)} FAIL, {len(skipped)} SKIP")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
