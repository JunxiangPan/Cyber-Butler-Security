from __future__ import annotations

import physical_separation


def test_missing_ack_is_not_separated(tmp_path):
    assert physical_separation.is_separated(tmp_path) is False


def test_acknowledged_separate_device(tmp_path):
    record = physical_separation.acknowledge(tmp_path, True)
    assert record["separate_device"] is True
    assert physical_separation.is_separated(tmp_path) is True


def test_same_host_ack_fails_closed(tmp_path):
    physical_separation.acknowledge(tmp_path, False)
    assert physical_separation.is_separated(tmp_path) is False
