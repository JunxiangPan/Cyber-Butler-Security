"""CEL policy evaluation backed by cel-python (optional dependency)."""
from __future__ import annotations

from typing import Any


class CelPolicyError(ValueError):
    """Raised when a CEL expression cannot be compiled or evaluated."""


def evaluate(expression: str, files: dict[str, str]) -> bool:
    """Evaluate one CEL expression against a file map.

    The activation exposes ``files`` as a list of ``{path, text}`` maps, so
    expressions can aggregate across files with ``files.exists(...)``.
    """
    try:
        import celpy
    except ImportError as exc:
        raise CelPolicyError("cel-policy requires the optional cel-python package") from exc
    activation: dict[str, Any] = {
        "files": list(files.values()),
        "paths": list(files),
    }
    try:
        environment = celpy.Environment()
        program = environment.program(environment.compile(expression))
        result = program.evaluate(activation)
    except Exception as exc:
        raise CelPolicyError(f"invalid CEL expression: {exc}") from exc
    return bool(result)
