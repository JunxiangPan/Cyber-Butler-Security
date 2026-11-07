"""CEL policy decisions for the five policy-driven gates."""
from __future__ import annotations

from .cel_policy import evaluate_context

POLICIES = {
    "comments": "size(findings) == 0",
    "claims": "ok",
    "dependency": "ok",
    "docs": "ok",
    "custom": "size(findings) == 0",
}


def decide(gate: str, context: dict, overrides: dict | None = None) -> bool:
    """Evaluate the gate's CEL policy against a detection context."""
    expression = (overrides or {}).get(gate, POLICIES.get(gate))
    if not expression:
        raise ValueError(f"no CEL policy configured for {gate}")
    return evaluate_context(str(expression), context)
