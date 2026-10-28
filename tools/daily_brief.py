#!/usr/bin/env python3
"""Morning brief from IT之家 and GitHub Trending, sent to QQ via AstrBot."""

from __future__ import annotations

import argparse
import datetime as dt
import sys
from pathlib import Path
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

ROOT = Path(r"YOUR_PROJECT_PATH")
TOKEN = ROOT / ".astrbot_token"
UMO = "qq_sujinyan:FriendMessage:YOUR_QQ_ID"
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36"
    )
}


def it_home(limit: int = 3) -> list[tuple[str, str]]:
    response = requests.get("https://www.ithome.com/", headers=HEADERS, timeout=20)
    response.raise_for_status()
    response.encoding = response.apparent_encoding or "utf-8"
    soup = BeautifulSoup(response.text, "lxml")
    items: list[tuple[str, str]] = []
    seen: set[str] = set()
    for anchor in soup.find_all("a", href=True):
        title = anchor.get_text(" ", strip=True)
        href = urljoin("https://www.ithome.com/", anchor["href"])
        if len(title) < 10 or "ithome.com" not in href:
            continue
        if not any(part in href for part in ("/0/", "/1/")):
            continue
        if title in seen:
            continue
        if any(bad in title for bad in ("登录", "注册", "下载", "APP", "广告", "排行", "收藏")):
            continue
        seen.add(title)
        items.append((title, href))
        if len(items) >= limit:
            break
    return items


def github_trending(limit: int = 3) -> list[tuple[str, str]]:
    response = requests.get(
        "https://github.com/trending?since=daily",
        headers=HEADERS,
        timeout=20,
    )
    response.raise_for_status()
    soup = BeautifulSoup(response.text, "lxml")
    items: list[tuple[str, str]] = []
    for article in soup.select("article.Box-row"):
        heading = article.select_one("h2 a")
        if not heading or not heading.get("href"):
            continue
        title = " ".join(heading.get_text(" ", strip=True).split())
        href = urljoin("https://github.com", heading["href"])
        if title:
            items.append((title, href))
        if len(items) >= limit:
            break
    return items


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
    today = dt.date.today().strftime("%Y-%m-%d")
    lines = [f"哥，早上好，今天的简报（{today}）："]
    try:
        for i, (title, url) in enumerate(it_home(), 1):
            lines.append(f"IT之家 {i}. {title}\n{url}")
    except Exception as exc:
        lines.append(f"IT之家抓取失败：{exc}")
    try:
        for i, (title, url) in enumerate(github_trending(), 1):
            lines.append(f"GitHub {i}. {title}\n{url}")
    except Exception as exc:
        lines.append(f"GitHub Trending 抓取失败：{exc}")
    text = "\n".join(lines)
    print(text)
    if args.no_send:
        return 0
    ok = send_qq(text)
    print("QQ_SENT" if ok else "QQ_SEND_FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
