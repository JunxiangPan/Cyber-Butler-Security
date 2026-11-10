"""OpenAI-compatible function-tool adapter for the CBS Broker v1 HTTP API.

The adapter is deliberately thin: it owns only the external tool schema and
HTTP mapping. Approval and execution remain in the Broker.
"""
from __future__ import annotations

from typing import Any

import requests

ADAPTER_NAME = "openai-function-tools"
ADAPTER_VERSION = "1.0.0"

TOOLS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "broker_request",
            "description": "Submit one approval-gated delete request to the local CBS Broker.",
            "parameters": {
                "type": "object",
                "properties": {
                    "target": {"type": "string"},
                    "reason": {"type": "string"},
                    "approval_only": {"type": "boolean"},
                },
                "required": ["target"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "broker_status",
            "description": "Read the approval status for a challenge id.",
            "parameters": {
                "type": "object",
                "properties": {"id": {"type": "string"}},
                "required": ["id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "broker_verify",
            "description": "Submit the human-supplied TOTP code for a pending request.",
            "parameters": {
                "type": "object",
                "properties": {"id": {"type": "string"}, "code": {"type": "string"}},
                "required": ["id", "code"],
            },
        },
    },
]


class BrokerToolAdapter:
    """External tool adapter with no direct filesystem or TOTP-secret access."""

    def __init__(self, base_url: str, token: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.headers = {"X-Broker-Token": token}

    def call(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        if name == "broker_request":
            response = requests.post(
                self.base_url + "/request",
                json={"action": "delete", "target": arguments["target"], "reason": arguments.get("reason", ""), "approval_only": bool(arguments.get("approval_only", False))},
                headers=self.headers, timeout=10,
            )
        elif name == "broker_status":
            response = requests.get(
                self.base_url + "/api/request_approval/status",
                params={"id": arguments["id"]}, headers=self.headers, timeout=10,
            )
        elif name == "broker_verify":
            response = requests.post(
                self.base_url + "/verify",
                json={"id": arguments["id"], "code": arguments["code"]},
                headers=self.headers, timeout=10,
            )
        else:
            raise ValueError(f"unknown tool: {name}")
        return {"http": response.status_code, "body": response.json()}
