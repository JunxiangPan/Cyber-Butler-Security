from __future__ import annotations

import json
import time

import wfp_tripwire


def test_parse_firewall_line():
    event = wfp_tripwire.parse_firewall_line(
        "2026-11-03 12:00:00 DROP TCP 10.0.0.2 8.8.8.8 50000 443 0 - - - RECEIVE"
    )
    assert event
    assert event["dst"] == "8.8.8.8"
    assert event["dst_port"] == "443"
    assert event["event"] == "NETWORK_EXFILTRATION_ATTEMPT"


def test_cursor_reads_once_and_rotates(tmp_path):
    log = tmp_path / "pfirewall.log"
    cursor = tmp_path / "cursor.json"
    log.write_text(
        "2026-11-03 12:00:00 DROP TCP 10.0.0.2 8.8.8.8 50000 443 0 - - - RECEIVE\n",
        encoding="utf-8",
    )
    first = wfp_tripwire.read_new(log, cursor)
    assert len(first) == 1
    assert wfp_tripwire.read_new(log, cursor) == []

    log.write_text(
        "2026-11-03 12:00:01 DROP TCP 10.0.0.2 1.1.1.1 50001 443 0 - - - RECEIVE extra-field\n",
        encoding="utf-8",
    )
    second = wfp_tripwire.read_new(log, cursor)
    assert len(second) == 1
    assert second[0]["dst"] == "1.1.1.1"
