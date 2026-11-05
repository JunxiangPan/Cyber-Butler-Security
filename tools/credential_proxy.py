"""Loopback credential proxy for agent API calls.

The agent is configured with a fake bearer token and a loopback base URL. This
process (run under the owner/service identity) replaces the fake token with the
real upstream key. The real key is never returned to the agent.

This is a reverse proxy, not a TLS MITM: the agent must be pointed at the local
base URL explicitly. Only ``/v1/`` paths on one fixed upstream are forwarded.
"""

from __future__ import annotations

import hmac
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_BODY = 4 * 1024 * 1024
ALLOWED_PREFIX = "/v1/"


@dataclass(frozen=True)
class ProxyConfig:
    """ProxyConfig helper/type."""
    upstream: str
    fake_token: str
    listen_host: str = "127.0.0.1"
    listen_port: int = 18091
    timeout: int = 120

    @classmethod
    def load(cls, path: Path) -> "ProxyConfig":
        """Load.
        
        Args:
            path: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
        upstream = str(data.get("upstream", "")).strip().rstrip("/")
        parsed = urllib.parse.urlparse(upstream)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise ValueError("upstream must be an absolute http(s) URL")
        fake = str(data.get("fake_token", "")).strip()
        if len(fake) < 16:
            raise ValueError("fake_token must be at least 16 characters")
        return cls(
            upstream=upstream,
            fake_token=fake,
            listen_host=str(data.get("listen_host", "127.0.0.1")),
            listen_port=int(data.get("listen_port", 18091)),
            timeout=int(data.get("timeout", 120)),
        )

    def real_key(self) -> str:
        """Real key.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        value = os.environ.get("CBS_CREDENTIAL_PROXY_REAL_KEY", "").strip()
        if not value:
            raise RuntimeError("CBS_CREDENTIAL_PROXY_REAL_KEY is not set")
        return value


class ProxyServer(ThreadingHTTPServer):
    """HTTP server carrying the immutable proxy configuration."""
    config: ProxyConfig


def _safe_path(path: str) -> str:
    """Safe path.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    parsed = urllib.parse.urlsplit(path)
    if not parsed.path.startswith(ALLOWED_PREFIX):
        raise ValueError("path is not under /v1/")
    if ".." in parsed.path.split("/"):
        raise ValueError("path traversal is not allowed")
    return urllib.parse.urlunsplit(("", "", parsed.path, parsed.query, ""))


class Handler(BaseHTTPRequestHandler):
    """Loopback HTTP handler that injects the real upstream credential."""

    @property
    def proxy_config(self) -> ProxyConfig:
        """Return the typed server configuration."""
        from typing import cast
        return cast(ProxyServer, self.server).config

    server_version = "CBS-CredentialProxy/1.0"

    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        """Send.
        
        Args:
            status: caller-supplied value.
            body: caller-supplied value.
            content_type: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        """Authorized.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        header = self.headers.get("Authorization", "")
        expected = "Bearer " + self.proxy_config.fake_token
        return hmac.compare_digest(header, expected)

    def _forward(self, method: str) -> None:
        """Forward.
        
        Args:
            method: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        if not self._authorized():
            self._send(401, b'{"ok":false,"error":"proxy token rejected"}')
            return
        try:
            path = _safe_path(self.path)
        except ValueError as exc:
            self._send(400, json.dumps({"ok": False, "error": str(exc)}).encode())
            return
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length > MAX_BODY:
            self._send(413, b'{"ok":false,"error":"request body too large"}')
            return
        body = self.rfile.read(length) if length else None
        headers = {
            "Authorization": "Bearer " + self.proxy_config.real_key(),
            "Accept": self.headers.get("Accept", "application/json"),
            "Content-Type": self.headers.get("Content-Type", "application/json"),
        }
        request = urllib.request.Request(
            self.proxy_config.upstream + path,
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=self.proxy_config.timeout) as response:
                payload = response.read()
                self._send(response.status, payload, response.headers.get("Content-Type", "application/json"))
        except urllib.error.HTTPError as exc:
            payload = exc.read()
            self._send(exc.code, payload, exc.headers.get("Content-Type", "application/json"))
        except (urllib.error.URLError, TimeoutError, OSError):
            self._send(502, json.dumps({"ok": False, "error": "upstream unavailable"}).encode())

    def do_GET(self) -> None:
        """Do get.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        self._forward("GET")

    def do_POST(self) -> None:
        """Do post.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        self._forward("POST")

    def log_message(self, format: str, *args) -> None:
        # Never log Authorization or request bodies.
        """Log message.
        
        Args:
            fmt: caller-supplied value.
            args: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        print("credential-proxy: " + format % args, flush=True)


def build_server(config: ProxyConfig) -> ProxyServer:
    """Build server.
    
    Args:
        config: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    server = ProxyServer((config.listen_host, config.listen_port), Handler)
    server.config = config
    return server


def main() -> int:
    """Main.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    config = ProxyConfig.load(Path(args.config))
    if args.check:
        config.real_key()
        print("credential-proxy config OK")
        return 0
    build_server(config).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
