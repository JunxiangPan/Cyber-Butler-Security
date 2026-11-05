from __future__ import annotations

import broker


def test_job_limits_are_bounded_and_disable_breakaway(monkeypatch):
    monkeypatch.setenv("CBS_BROKER_JOB_MEMORY_MB", "4096")
    monkeypatch.setenv("CBS_BROKER_PROCESS_MEMORY_MB", "2048")
    monkeypatch.setenv("CBS_BROKER_JOB_CPU_SECONDS", "600")
    monkeypatch.setenv("CBS_BROKER_ACTIVE_PROCESS", "16")

    flags, limits = broker._job_limit_flags()

    assert flags & broker.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    assert flags & broker.JOB_OBJECT_LIMIT_PROCESS_MEMORY
    assert flags & broker.JOB_OBJECT_LIMIT_JOB_MEMORY
    assert flags & broker.JOB_OBJECT_LIMIT_JOB_TIME
    assert flags & broker.JOB_OBJECT_LIMIT_ACTIVE_PROCESS
    assert not flags & 0x00000800  # BREAKAWAY_OK must never be set
    assert not flags & 0x00000400  # SILENT_BREAKAWAY_OK must never be set
    assert limits == {
        "memory_mb": 4096,
        "process_memory_mb": 2048,
        "cpu_seconds": 600,
        "active_process": 16,
    }


def test_job_limits_clamp_invalid_values(monkeypatch):
    monkeypatch.setenv("CBS_BROKER_JOB_MEMORY_MB", "-1")
    monkeypatch.setenv("CBS_BROKER_ACTIVE_PROCESS", "9999")
    _, limits = broker._job_limit_flags()
    assert limits["memory_mb"] >= 64
    assert limits["active_process"] <= 256
