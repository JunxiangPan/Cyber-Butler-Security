"""Release-artifact and Python environment integrity checks."""
from __future__ import annotations

import ast
import hashlib
import re
import zipfile
from pathlib import Path

from .config import GateConfig

SKIP_PARTS = {".git", ".venv", "__pycache__", "node_modules", "wheelhouse", "qa-temp", "build"}
SKIP_PREFIXES = ("quality/", "checks/", "tests/", "tools/audit_", "tools/red_team", "tools/package_release", "tools/prune_", "tools/restructure_", "tools/rewrite_")
BAD_NAMES = {"netstat", "netstat.exe", "powershell", "powershell.exe", "pwsh", "pwsh.exe", "cmd", "cmd.exe"}


def artifact_findings(cfg: GateConfig) -> list[str]:
    """Verify configured artifacts inside an optional package ZIP."""
    required = getattr(cfg, "required_artifacts", ()) or ()
    if not getattr(cfg, "package_zip", None):
        return []
    if not required:
        return ["package_zip is configured but required_artifacts is empty"]
    zip_path = Path(cfg.package_zip)
    if not zip_path.is_file():
        return [f"package zip missing: {zip_path}"]
    findings: list[str] = []
    try:
        with zipfile.ZipFile(zip_path) as archive:
            names = set(archive.namelist())
            manifest: dict[str, str] = {}
            if "update-manifest.json" in names:
                import json
                data = json.loads(archive.read("update-manifest.json").decode("utf-8"))
                manifest = {str(item["path"]): str(item["sha256"]) for item in data.get("files", [])}
            for item in required:
                path = str(item.get("path")) if isinstance(item, dict) else str(item)
                expected = str(item.get("sha256", "")) if isinstance(item, dict) else manifest.get(path, "")
                if path not in names:
                    findings.append(f"required artifact missing from zip: {path}")
                    continue
                if expected:
                    digest = hashlib.sha256(archive.read(path)).hexdigest()
                    if digest.lower() != expected.lower():
                        findings.append(f"required artifact hash mismatch: {path}")
    except (OSError, zipfile.BadZipFile, ValueError) as exc:
        return [f"cannot inspect package zip: {exc}"]
    return findings


def _is_absolute_command(value: str) -> bool:
    return value.startswith(("\\", "/")) or (len(value) > 2 and value[1] == ":")


PATH_ESCAPE = None  # line-based check below avoids regex escaping ambiguity


def path_escape_findings(cfg: GateConfig) -> list[str]:
    """Reject hard-coded Windows paths whose backslash becomes an escape."""
    findings: list[str] = []
    for path in list(cfg.root.rglob("*.py")) + list(cfg.root.rglob("*.ps1")):
        if SKIP_PARTS & set(path.parts):
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if "C:\\" in line and any(token in line for token in ("\t", "\n", "\r")):
                findings.append(f"{path.relative_to(cfg.root).as_posix()}:{line_no}: ambiguous Windows path escape; use os.path.join or escaped slashes")
    return findings


def python_env_findings(cfg: GateConfig) -> list[str]:
    """Reject obvious PATH-dependent subprocess calls and missing sys.path guards."""
    findings: list[str] = []
    for path in cfg.root.rglob("*.py"):
        rel = path.relative_to(cfg.root).as_posix()
        if SKIP_PARTS & set(path.parts) or rel.startswith(SKIP_PREFIXES):
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except (OSError, SyntaxError):
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call) or not node.args:
                continue
            func = node.func
            name = ""
            if isinstance(func, ast.Attribute):
                name = func.attr
            if name not in {"run", "Popen", "call", "check_output", "system"}:
                continue
            first = node.args[0]
            command = ""
            if isinstance(first, ast.Constant) and isinstance(first.value, str):
                command = first.value
            elif isinstance(first, (ast.List, ast.Tuple)) and first.elts:
                head = first.elts[0]
                if isinstance(head, ast.Constant) and isinstance(head.value, str):
                    command = head.value
            if command:
                token = command.strip().split()[0] if command.strip() else ""
                base = Path(token).name.lower()
                if base in BAD_NAMES and not _is_absolute_command(token):
                    findings.append(f"{path.relative_to(cfg.root).as_posix()}:{node.lineno}: naked external command {token!r}")
    for name in ("tools/broker.py", "webui/run.py"):
        path = cfg.root / name
        if path.is_file() and "sys.path.insert" not in path.read_text(encoding="utf-8"):
            findings.append(f"{name}: missing sys.path.insert bootstrap")
    for path in list(cfg.root.rglob("*.bat")) + list(cfg.root.rglob("*.ps1")):
        if SKIP_PARTS & set(path.parts):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for line in text.splitlines():
            if "PYTHONPATH" in line and "=" in line:
                if "tools" not in line:
                    findings.append(f"{path.relative_to(cfg.root).as_posix()}: PYTHONPATH must include tools/")
                    break
    return findings


def check(cfg: GateConfig) -> list[str]:
    """Run both release-integrity checks."""
    return artifact_findings(cfg) + python_env_findings(cfg) + path_escape_findings(cfg)
