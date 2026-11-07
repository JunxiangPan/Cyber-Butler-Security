"""CEL policy evaluation backed by cel-python (optional dependency)."""
from __future__ import annotations

from typing import Any


class CelPolicyError(ValueError):
    """Raised when a CEL expression cannot be compiled or evaluated."""


def evaluate_context(expression: str, activation: dict[str, Any]) -> bool:
    """Evaluate a CEL expression against an explicit activation map."""
    try:
        import celpy
    except ImportError as exc:
        raise CelPolicyError("cel-policy requires the optional cel-python package") from exc
    try:
        environment = celpy.Environment()
        program = environment.program(environment.compile(expression))
        result = program.evaluate(activation)
    except Exception as exc:
        raise CelPolicyError(f"invalid CEL expression: {exc}") from exc
    return bool(result)


def evaluate(expression: str, files: dict[str, str]) -> bool:
    """Evaluate one CEL expression against a file map."""
    return evaluate_context(expression, {"files": list(files.values()), "paths": list(files)})
