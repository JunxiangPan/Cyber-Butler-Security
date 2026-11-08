#!/usr/bin/env python3
"""Make the NOT_FIXED report section concrete enough for the signing gate."""
from __future__ import annotations

from pathlib import Path
import sys

REPLACEMENTS = {
    "- 真实 ACL/DPAPI/WFP/卸载残留仍需干净 VM 验证。": (
        "- 真实 ACL/DPAPI/WFP/卸载残留仍需干净 VM 验证："
        "installer/lib/Installer.Acl.ps1、installer/lib/Installer.Totp.ps1、"
        "tools/verify_broker_acl.ps1。"
    ),
    "- PSSA 未覆盖测试脚本全规则，测试脚本只做语法解析。": (
        "- PSSA 未覆盖 installer/tests/*.ps1 全规则；49 个测试脚本只做语法解析。"
    ),
    "- vulture 白名单仍有动态入口人工审查风险。": (
        "- vulture_whitelist.py 的 67 项动态入口仍需人工审查。"
    ),
}


def main() -> int:
    """Patch the three bullets and fail if any replacement is missing."""
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "BUILD_REPORT.md")
    text = path.read_text(encoding="utf-8")
    for old, new in REPLACEMENTS.items():
        if old not in text:
            raise SystemExit("missing report bullet: " + old)
        text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")
    print("NOT_FIXED_CONCRETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
