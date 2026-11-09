"""CBS Broker Python client.

The client is loopback-only. It never reads TOTP material and never bypasses
the Broker's approval state. It only calls the documented endpoints.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class CbsError(RuntimeError):
    """Raised when the Broker returns an error envelope."""

    def __init__(self, status: int, body: dict):
        self.status = status
        self.body = body
        super().__init__(f"CBS Broker error {status}: {body.get('error', body)}")


class CbsClient:
    """Small synchronous client for the CBS Broker v1 API."""

    def __init__(
        self,
        base_url: str = "http://127.0.0.1:18090",
        token: str | None = None,
        token_path: str | Path = "tools/broker_token.txt",
        timeout: float = 10.0,
    ):
        """Create a client bound to a loopback Broker."""
        if not base_url.startswith(("http://127.0.0.1:", "http://localhost:")):
            raise ValueError("CBS Broker client only accepts loopback URLs")
        self.base_url = base_url.rstrip("/")
        self.token = token or os.environ.get("CBS_BROKER_TOKEN") or self._read_token(Path(token_path))
        self.timeout = timeout

    @staticmethod
    def _read_token(path: Path) -> str:
        """Read a Broker token from a file, rejecting empty values."""
        if not path.is_file():
            raise FileNotFoundError(f"Broker token not found: {path}")
        value = path.read_text(encoding="utf-8").strip()
        if not value:
            raise ValueError(f"Broker token is empty: {path}")
        return value

    def _call(self, method: str, path: str, payload: dict | None = None) -> dict:
        """Call one Broker endpoint and return its JSON object."""
        url = self.base_url + path
        data = None
        headers = {"X-Broker-Token": self.token, "Accept": "application/json"}
        if payload is not None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json; charset=utf-8"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            try:
                body = json.loads(exc.read().decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                body = {"error": str(exc)}
            raise CbsError(exc.code, body) from exc
        except urllib.error.URLError as exc:
            raise CbsError(0, {"error": str(exc.reason)}) from exc

    def request_approval(self, action: str, target: str, *, reason: str = "", approval_only: bool = True) -> dict:
        """Create an approval request; the Broker decides whether TOTP is required."""
        return self._call("POST", "/request", {
            "action": action,
            "target": target,
            "reason": reason,
            "approval_only": approval_only,
        })

    def status(self, challenge_id: str) -> dict:
        """Read approval status for one challenge."""
        query = urllib.parse.urlencode({"id": challenge_id})
        return self._call("GET", "/api/request_approval/status?" + query)

    def verify(self, challenge_id: str, code: str) -> dict:
        """Submit a TOTP code; the Broker executes the approved action."""
        return self._call("POST", "/verify", {"id": challenge_id, "code": code})

    def wait_for_approval(self, challenge_id: str, *, timeout: float = 180.0, interval: float = 2.0) -> dict:
        """Poll until the request leaves pending, or raise on timeout."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            body = self.status(challenge_id)
            if body.get("status") != "pending":
                return body
            time.sleep(interval)
        raise TimeoutError(f"approval did not leave pending within {timeout:.0f}s")
