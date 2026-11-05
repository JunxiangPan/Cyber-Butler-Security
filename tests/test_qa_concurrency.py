from __future__ import annotations

import concurrent.futures
from pathlib import Path

import broker


def test_ten_concurrent_requests_do_not_deadlock_or_500(monkeypatch, tmp_path):
    tmp = tmp_path / "tmp"
    memory = tmp_path / "memory"
    vault = tmp_path / "vault"
    shared = tmp_path / "shared"
    for path in (tmp, memory, vault, shared):
        path.mkdir(parents=True, exist_ok=True)
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    monkeypatch.setenv("CBS_DISABLE_JITTER", "1")
    broker.broker_state._pending = None
    broker._send_events.clear()
    broker._send_results.clear()
    broker.broker_state._last_request_at = 0.0

    def one(index: int):
        return broker.run_request({
            "action": "write_file",
            "target": str(memory / f"concurrent-{index}.txt"),
            "content": f"value-{index}",
        })

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        results = list(pool.map(one, range(10)))

    statuses = [status for status, _ in results]
    assert 200 in statuses
    assert all(status in {200, 409, 429} for status in statuses), statuses
    assert not any(status == 500 for status in statuses)
    assert all(isinstance(body, dict) for _, body in results)
