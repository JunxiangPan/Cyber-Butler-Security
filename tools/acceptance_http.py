#!/usr/bin/env python3
"""Send one acceptance JSON request without PowerShell body re-encoding."""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request


def main() -> int:
    """Post one JSON request and print a JSON result envelope."""
    url = os.environ.get("CBS_ACCEPTANCE_URL", "")
    method = os.environ.get("CBS_ACCEPTANCE_METHOD", "GET")
    body_text = os.environ.get("CBS_ACCEPTANCE_BODY", "")
    token = os.environ.get("CBS_ACCEPTANCE_TOKEN", "")
    headers = {
        "X-Broker-Token": token,
        "Content-Type": "application/json; charset=utf-8",
    }
    data = body_text.encode("utf-8") if body_text else None
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    status = 0
    body = ""
    exit_code = 0
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status = int(response.status)
            body = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        status = int(exc.code)
        body = exc.read().decode("utf-8", errors="replace")
    except Exception as exc:  # noqa: BLE001 - failure is reported as a result
        body = str(exc)
        exit_code = 1
    payload = {
        "status": str(status),
        "body": body,
        "raw": body.strip() + "\nHTTP_STATUS:" + str(status) + "\nEXIT:" + str(exit_code),
        "exit": exit_code,
    }
    print(json.dumps(payload, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
