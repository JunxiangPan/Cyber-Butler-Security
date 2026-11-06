"""Tests for the sample package."""
from sample_project import add


def test_add() -> None:
    """The sample function adds two integers."""
    assert add(2, 3) == 5
