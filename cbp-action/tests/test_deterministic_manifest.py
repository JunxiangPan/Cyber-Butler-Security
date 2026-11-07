"""SOURCE_DATE_EPOCH makes manifest time deterministic."""
from tools.dogfood_manifest import _now


def test_source_date_epoch_is_used(monkeypatch) -> None:
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "0")
    assert _now() == _now()
    assert _now().startswith("1970-01-01T00:00:00")
