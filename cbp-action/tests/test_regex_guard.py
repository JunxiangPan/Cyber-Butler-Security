"""Hard-timeout wrapper tests."""
import subprocess
from cbp import regex_guard


def test_regex_guard_returns_line_numbers() -> None:
    assert regex_guard.find_lines("bad", 0, "ok\nbad\n") == [2]


def test_regex_guard_times_out_when_worker_does(monkeypatch) -> None:
    def fake_run(*args, **kwargs):
        raise subprocess.TimeoutExpired(cmd="worker", timeout=0.01)
    monkeypatch.setattr(regex_guard.subprocess, "run", fake_run)
    try:
        regex_guard.find_lines("(a+)+$", 0, "a" * 40 + "b", timeout=0.01)
    except regex_guard.RegexTimeout:
        pass
    else:
        raise AssertionError("timeout was not propagated")
