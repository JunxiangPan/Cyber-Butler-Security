#!/usr/bin/env python3
"""Daily AstrBot operation audit, sent to QQ through AstrBot's Open API."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

import requests

ROOT = Path(r"YOUR_PROJECT_PATH")
LOG = ROOT / "AstrBot" / "data" / "service-astrbot.out.log"
TOKEN = ROOT / ".astrbot_token"
REPORT = ROOT / "tools" / "daily-audit.jsonl"
UMO = "qq_sujinyan:FriendMessage:YOUR_QQ_ID"
SHARED = r"YOUR_USER_PATH\Desktop\大肥鱼专用文件夹"


def strip_ansi(text: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", text)


def build_report() -> dict:
    if not LOG.exists():
        return {"date": dt.date.today().isoformat(), "error": "AstrBot log missing"}
    text = strip_ansi(LOG.read_text(encoding="utf-8", errors="ignore"))
    tool_names = re.findall(r"使用工具：([A-Za-z0-9_\-]+)", text)
    agent_tools = re.findall(r"Agent 使用工具: \[([^\]]+)\]", text)
    for group in agent_tools:
        tool_names.extend(re.findall(r"'([^']+)'", group))
    # A tool can appear in both lines; count unique tool invocations by the
    # "使用工具：" line and add agent-only entries that are not duplicated.
    tool_calls = len(re.findall(r"使用工具：", text))
    files = sorted(set(re.findall(re.escape(SHARED) + r"[^\s\"')\]]+", text)))
    code_calls = len(re.findall(r"使用工具：astrbot_execute_python", text))
    denied = re.findall(
        r"访问被拒绝|Access is denied|Access denied|permission denied|越权|Permission denied",
        text,
        flags=re.IGNORECASE,
    )
    return {
        "date": dt.date.today().isoformat(),
        "files": files,
        "file_count": len(files),
        "tool_calls": tool_calls,
        "code_calls": code_calls,
        "denied_count": len(denied),
        "tool_names": sorted(set(tool_names)),
    }


def send_qq(text: str) -> bool:
    if not TOKEN.exists():
        return False
    token = TOKEN.read_text(encoding="utf-8").strip()
    try:
        response = requests.post(
            "http://127.0.0.1:6185/api/v1/im/messages",
            headers={"Authorization": f"Bearer {token}"},
            json={"umo": UMO, "message": text},
            timeout=15,
        )
        return response.ok
    except requests.RequestException:
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-send", action="store_true")
    args = parser.parse_args()
    report = build_report()
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    with REPORT.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(report, ensure_ascii=False) + "\n")
    text = (
        f"哥，今天（{report['date']}）的审计报告：\n"
        f"处理文件：{report['file_count']} 个\n"
        f"工具调用：{report['tool_calls']} 次\n"
        f"写代码：{report['code_calls']} 段\n"
        f"越权/权限拒绝：{report['denied_count']} 次\n"
    )
    if report["file_count"]:
        text += "涉及文件：" + "、".join(Path(p).name for p in report["files"][:5])
        if report["file_count"] > 5:
            text += f" 等 {report['file_count']} 个"
        text += "\n"
    if report["denied_count"]:
        text += "检测到权限拒绝记录，建议查看 tools\\snowluma_guard.log。"
    else:
        text += "未检测到越权行为。"
    print(text)
    if not args.no_send:
        ok = send_qq(text)
        print("QQ_SENT" if ok else "QQ_SEND_FAILED")
        return 0 if ok else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
