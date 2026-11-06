"""Concurrency checks for the broker's approval lock."""
from __future__ import annotations

import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


class _FakeTotp:
    def __init__(self, secret: str) -> None:
        self.secret = secret

    def verify(self, code: str, valid_window: int = 0) -> bool:
        return code == "123456"


def test_ten_concurrent_approvals_only_one_consumes_code(monkeypatch) -> None:
    monkeypatch.setattr(broker, "secret", lambda: "test-secret")
    monkeypatch.setattr(broker.pyotp, "TOTP", _FakeTotp)
    broker.broker_state._used_totp.clear()
    barrier = threading.Barrier(10)
    results: list[str] = []
    lock = threading.Lock()

    def worker() -> None:
        barrier.wait(timeout=10)
        value = broker.verify_code("123456", "approval-race")
        with lock:
            results.append(value)

    threads = [threading.Thread(target=worker) for _ in range(10)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=10)
    assert not any(thread.is_alive() for thread in threads)
    assert results.count("totp") == 1
    assert results.count("replay") == 9
