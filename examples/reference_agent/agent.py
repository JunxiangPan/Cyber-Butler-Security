#!/usr/bin/env python3
"""Minimal reference agent: route one destructive intent through CBS and wait."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from sdk.python.cbs_client import CbsClient


def main() -> int:
    """Submit one approval request and, when supplied, submit the TOTP code."""
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path)
    parser.add_argument("--base-url", default="http://127.0.0.1:18090")
    args = parser.parse_args()
    target = args.target.resolve()
    if not target.is_file():
        print("REFERENCE_AGENT_TARGET_NOT_FILE", target, file=sys.stderr)
        return 2
    client = CbsClient(args.base_url)
    request = client.request_approval("delete", str(target), reason="reference-agent demo")
    print("REFERENCE_AGENT_REQUEST", request.get("id"), request.get("status"))
    status = client.wait_for_approval(str(request["id"]))
    print("REFERENCE_AGENT_STATUS", status.get("status"))
    code = os.environ.get("CBS_TOTP", "").strip()
    if status.get("status") == "approved" and code:
        result = client.verify(str(request["id"]), code)
        print("REFERENCE_AGENT_VERIFIED", result.get("status"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
