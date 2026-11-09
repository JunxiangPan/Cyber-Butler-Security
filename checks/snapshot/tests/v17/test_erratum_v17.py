from tools.erratum_v17 import mark


def test_erratum_is_machine_readable_and_preserves_body() -> None:
    body = "# v1.7.0\n\nold evidence"
    result = mark(body, "hash mismatch")
    assert result.startswith("ERRATUM:\n\nhash mismatch\n\n")
    assert "old evidence" in result
    assert mark(result, "again") == result
