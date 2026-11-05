#!/usr/bin/env python3
"""Check an AgentRuntime overlay against a source tree without importing it.

The checker parses imports from every overlay Python file, resolves the
imported module in the official source tree first (and optionally in the
overlay), and verifies that each imported symbol is defined there.

Usage:
    python tools/check-overlay-compat.py \
        --official-source D:\\tmp\\AgentRuntime-4.29.3 \
        --overlay overlay \
        --expected-version 4.29.3
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    """Sha256.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_version(root: Path) -> str:
    """Source version.
    
    Args:
        root: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    pyproject = root / "pyproject.toml"
    if not pyproject.exists():
        return ""
    match = re.search(r'^version\s*=\s*"([^"]+)"', pyproject.read_text(encoding="utf-8-sig"), re.M)
    return match.group(1) if match else ""


def module_file(root: Path, module: str) -> Path | None:
    """Module file.
    
    Args:
        root: caller-supplied value.
        module: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    parts = module.split(".")
    base = root / Path(*parts)
    for candidate in (base.with_suffix(".py"), base / "__init__.py"):
        if candidate.is_file():
            return candidate
    return None


def top_level_symbols(path: Path) -> set[str]:
    """Top level symbols.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
    except (OSError, SyntaxError):
        return set()
    names: set[str] = set()
    for node in tree.body:
        if isinstance(node, (ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    names.add(target.id)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            names.add(node.target.id)
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            for alias in node.names:
                names.add(alias.asname or alias.name.split(".")[0])
    return names


def resolve_relative(module: str, level: int, file_rel: str) -> str:
    """Resolve relative.
    
    Args:
        module: caller-supplied value.
        level: caller-supplied value.
        file_rel: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if level <= 0:
        return module
    # Relative imports are anchored at the package containing this module, not
    # at the module itself. One dot means that package; two dots its parent.
    package = Path(file_rel).parent.as_posix().replace("/", ".")
    parts = package.split(".") if package not in {"", "."} else []
    if level > 1:
        parts = parts[: -(level - 1)] if level - 1 <= len(parts) else []
    return ".".join(parts + ([module] if module else []))


def check_import(
    node: ast.ImportFrom | ast.Import,
    *,
    file_rel: str,
    official: Path,
    overlay: Path,
) -> list[dict]:
    """Check import.
    
    Args:
        node: caller-supplied value.
        file_rel: caller-supplied value.
        official: caller-supplied value.
        overlay: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    findings: list[dict] = []
    if isinstance(node, ast.Import):
        for alias in node.names:
            if alias.name.startswith("agentruntime"):
                if module_file(official, alias.name) is None and module_file(overlay, alias.name) is None:
                    findings.append({"module": alias.name, "symbol": None, "reason": "module missing"})
        return findings

    module = resolve_relative(node.module or "", node.level, file_rel)
    if not module.startswith("agentruntime"):
        return findings
    official_module = module_file(official, module)
    overlay_module = module_file(overlay, module)
    if official_module is None and overlay_module is None:
        findings.append({"module": module, "symbol": None, "reason": "module missing"})
        return findings
    official_symbols = top_level_symbols(official_module) if official_module else set()
    overlay_symbols = top_level_symbols(overlay_module) if overlay_module else set()
    for alias in node.names:
        if alias.name == "*":
            continue
        # ``from package import submodule`` is valid even when the package's
        # __init__ does not re-export the name.
        if module_file(official, module + "." + alias.name) is not None or module_file(overlay, module + "." + alias.name) is not None:
            continue
        if alias.name not in official_symbols and alias.name not in overlay_symbols:
            findings.append({
                "module": module,
                "symbol": alias.name,
                "reason": "symbol missing in official source and overlay",
            })
    return findings


def main() -> int:
    """Main.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-source", required=True)
    parser.add_argument("--overlay", required=True)
    parser.add_argument("--expected-version", default="4.29.3")
    parser.add_argument("--include-overlay-symbols", action="store_true")
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    official = Path(args.official_source).resolve()
    overlay = Path(args.overlay).resolve()
    official_agentruntime = official / "agentruntime"
    actual_version = source_version(official)
    version_ok = actual_version == args.expected_version
    files: list[dict] = []
    for path in sorted(overlay.rglob("*.py")):
        if "__pycache__" in path.parts:
            continue
        rel = path.relative_to(overlay).as_posix()
        official_path = official / rel
        overlay_symbols: set[str] = set()
        findings: list[dict] = []
        try:
            tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
        except (OSError, SyntaxError) as exc:
            files.append({
                "path": rel,
                "status": "parse_error",
                "error": str(exc),
                "official_exists": official_path.is_file(),
            })
            continue
        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                findings.extend(check_import(
                    node,
                    file_rel=rel,
                    official=official,
                    overlay=overlay,
                ))
        if not version_ok:
            status = "version_mismatch"
        elif findings:
            status = "missing_dependency"
        elif official_path.is_file():
            status = "ok"
        else:
            status = "ok"
        entry = {
            "path": rel,
            "status": status,
            "official_exists": official_path.is_file(),
            "official_sha256": sha256(official_path) if official_path.is_file() else None,
            "overlay_sha256": sha256(path),
            "missing": findings,
            "official_missing_provided_by_overlay": sorted({
                item["module"] + ":" + str(item["symbol"])
                for item in findings
                if item.get("symbol")
            }),
            "depends_on": sorted({
                item["module"].replace(".", "/") + ".py"
                for item in findings
                if item.get("module")
            }),
        }
        files.append(entry)

    result = {
        "schema": 1,
        "official_source": str(official),
        "overlay": str(overlay),
        "based_on_agentruntime_version": args.expected_version,
        "official_version": actual_version,
        "version_ok": version_ok,
        "files": files,
    }
    text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if version_ok and not any(item["status"] == "missing_dependency" for item in files) else 1


if __name__ == "__main__":
    sys.exit(main())
