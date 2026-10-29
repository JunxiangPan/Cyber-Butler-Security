import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))

from email_approval import parse_approval_line, sender_allowed


def test_parse_approval_line_valid():
    assert parse_approval_line("APPROVE #A9F2 TOTP 123456") == ("A9F2", "123456")


def test_parse_approval_line_ignores_quoted_text():
    text = "\nAPPROVE #a9f2 TOTP 654321\n\nOn ... wrote:\nAPPROVE #BEEF TOTP 000000\n"
    assert parse_approval_line(text) == ("A9F2", "654321")


def test_parse_approval_line_rejects_trailing_text():
    assert parse_approval_line("APPROVE #A9F2 TOTP 123456 please") is None


def test_sender_allowed_exact_address():
    assert sender_allowed("Owner <owner@example.com>", "owner@example.com")
    assert not sender_allowed("Owner <owner@example.com.evil.test>", "owner@example.com")
    assert not sender_allowed("other@example.com", "owner@example.com")
