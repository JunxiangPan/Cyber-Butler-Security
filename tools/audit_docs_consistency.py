#!/usr/bin/env python3
"""Documentation consistency gate and DOC_STATUS_REPORT.md generator.

- Extracts Python/HTTP feature routes from source (AST).
- Compares the heading structure of the 8 localized READMEs.
- Scans for deprecated terms unless the line marks them historical.
- Writes DOC_STATUS_REPORT.md even when it fails.
No regex is used for Markdown heading detection; it is a line-oriented syntax
parser for the small Markdown subset we own.
"""
from __future__ import annotations

import ast
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
README = {
    "en": ROOT / "README_en.md",
    "zh": ROOT / "README_zh.md",
    "de": ROOT / "README_de.md",
    "es": ROOT / "README_es.md",
    "fr": ROOT / "README_fr.md",
    "ja": ROOT / "README_ja.md",
    "ko": ROOT / "README_ko.md",
    "ru": ROOT / "README_ru.md",
}
BASE = ROOT / "README.md"
DEPRECATED_TERMS = ("S4U", "Task Scheduler", "AgentRuntime Service", "计划任务")
HISTORICAL_MARKERS = (
    "historical", "deprecated", "legacy", "archive", "history",
    "历史", "已废弃", "旧版", "不再使用", "迁移",
)


def headings(path: Path) -> list[tuple[int, str]]:
    """Headings.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    result: list[tuple[int, str]] = []
    if not path.is_file():
        return result
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        stripped = line.lstrip()
        if not stripped.startswith("#"):
            continue
        level = len(stripped) - len(stripped.lstrip("#"))
        if level < 1 or level > 6:
            continue
        title = stripped[level:].strip()
        if title:
            result.append((level, title))
    return result


def feature_routes() -> list[str]:
    """Feature routes.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    path = ROOT / "webui" / "app.py"
    if not path.is_file():
        return []
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except SyntaxError:
        return []
    routes: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        for decorator in node.decorator_list:
            if not isinstance(decorator, ast.Call):
                continue
            func = decorator.func
            if not isinstance(func, ast.Attribute) or func.attr not in {"get", "post", "put", "delete"}:
                continue
            if decorator.args and isinstance(decorator.args[0], ast.Constant):
                value = decorator.args[0].value
                if isinstance(value, str):
                    routes.append(value)
    return sorted(set(routes))


def deprecated_findings() -> list[str]:
    """Deprecated findings.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    findings: list[str] = []
    candidates = [BASE] + list(README.values())
    candidates += [
        path for path in sorted((ROOT / "docs").rglob("*.md"))
        if "releases" not in path.parts and path.name != "S4U_AUDIT_v1.6.2.md"
    ]
    for path in candidates:
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith(("docs/40-history/", "docs/90-audit/")):
            continue
        text = path.read_text(encoding="utf-8-sig")
        header = chr(10).join(text.splitlines()[:20]).casefold()
        if any(marker.casefold() in header for marker in HISTORICAL_MARKERS):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            lowered = line.casefold()
            if any(marker.casefold() in lowered for marker in HISTORICAL_MARKERS):
                continue
            for term in DEPRECATED_TERMS:
                if term.casefold() in lowered:
                    findings.append(f"{path.relative_to(ROOT).as_posix()}:{number}: deprecated term {term}")
    return findings


def main() -> int:
    """Main.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    base = headings(BASE)
    base_counts = {level: sum(1 for item_level, _ in base if item_level == level) for level in range(1, 7)}
    rows = []
    problems: list[str] = []
    for language, path in README.items():
        items = headings(path)
        counts = {level: sum(1 for item_level, _ in items if item_level == level) for level in range(1, 7)}
        missing = {
            level: max(0, base_counts[level] - counts[level])
            for level in range(1, 7)
        }
        language_problems = [f"missing H{level}:{count}" for level, count in missing.items() if count]
        if language_problems:
            problems.append(f"DOC_INCONSISTENCY_ERROR {language}: " + ", ".join(language_problems))
        rows.append((language, path.name, len(items), counts, language_problems))
    deprecated = deprecated_findings()
    problems.extend(deprecated)
    routes = feature_routes()

    report = [
        "# DOC_STATUS_REPORT",
        "",
        f"- Version: {(ROOT / 'VERSION').read_text(encoding='utf-8').strip()}",
        f"- README languages: {len(README)}",
        f"- Feature routes extracted: {len(routes)}",
        f"- Status: {'PASS' if not problems else 'FAIL'}",
        "",
        "## Feature routes (source of truth)",
        "",
    ]
    report += [f"- `{route}`" for route in routes] or ["- none"]
    report += [
        "",
        "## Localized README structure",
        "",
        "| Language | File | Headings | H1 | H2 | H3 | Missing vs README.md |",
        "|---|---|---:|---:|---:|---:|---|",
    ]
    for language, name, total, counts, issues in rows:
        report.append(
            f"| {language} | {name} | {total} | {counts[1]} | {counts[2]} | {counts[3]} | "
            + (", ".join(issues) if issues else "none")
            + " |"
        )
    report += ["", "## Deprecated term findings", ""]
    report += [f"- {item}" for item in deprecated] or ["- none"]
    report += ["", "## Problems", ""]
    report += [f"- {item}" for item in problems] or ["- none"]
    (ROOT / "DOC_STATUS_REPORT.md").write_text("\n".join(report) + "\n", encoding="utf-8")

    if problems:
        print("DOC_CONSISTENCY_GATE_FAILED", file=sys.stderr)
        for item in problems[:200]:
            print("  " + item, file=sys.stderr)
        return 1
    print("DOC_CONSISTENCY_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
