"""CEL policy engine tests (cel-python is an optional test dependency)."""
import pytest
from cbp.cel_policy import CelPolicyError, evaluate


def test_any_and_not_across_files() -> None:
    files = {"a.py": "safe", "b.py": "secret = 1"}
    assert evaluate('files.exists(t, t.matches(".*secret.*"))', files) is True
    assert evaluate('files.exists(t, t.matches(".*secret.*")) && !files.exists(t, t.matches(".*allow.*"))', files) is True


def test_invalid_expression_is_explicit() -> None:
    with pytest.raises(CelPolicyError):
        evaluate("files.exists(", {"a.py": "x"})
