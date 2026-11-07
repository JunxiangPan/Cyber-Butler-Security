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


def apply(gate: str, passed: bool, detail: str, cfg) -> tuple[bool, str]:
    """Apply the CEL policy to a gate's detection result."""
    overrides = getattr(cfg, "cel_policies", {}) or {}
    context = {"ok": bool(passed), "findings": [] if passed else [detail]}
    try:
        decided = decide(gate, context, overrides)
    except Exception as exc:
        return False, f"{gate}: CEL policy failed: {exc}"
    return decided, detail
