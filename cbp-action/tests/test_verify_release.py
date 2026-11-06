"""Post-release audit must report ERRATA when the online body changes."""
from __future__ import annotations

from pathlib import Path

from cbp import verify_release


def test_matching_body_passes(tmp_path: Path, monkeypatch) -> None:
    body = tmp_path / "RELEASE_BODY.md"
    body.write_bytes(b"line one\r\nline two\r\n")
    monkeypatch.setattr(verify_release, "fetch_release_body", lambda repo, tag, token: "line one\nline two\n")
    passed, detail = verify_release.verify("owner/repo", "v1.0.0", body)
    assert passed is True
    assert "RELEASE_BODY_OK" in detail


def test_edited_online_body_fails(tmp_path: Path, monkeypatch) -> None:
    body = tmp_path / "RELEASE_BODY.md"
    body.write_text("original\n", encoding="utf-8")
    monkeypatch.setattr(verify_release, "fetch_release_body", lambda repo, tag, token: "silently edited\n")
    passed, detail = verify_release.verify("owner/repo", "v1.0.0", body)
    assert passed is False
    assert "ERRATA" in detail


def test_missing_local_body_fails(tmp_path: Path) -> None:
    passed, detail = verify_release.verify("owner/repo", "v1.0.0", tmp_path / "missing.md")
    assert passed is False
    assert "local release body missing" in detail


def test_cli_verify_requires_repository(monkeypatch, capsys) -> None:
    from cbp import cli
    monkeypatch.delenv("GITHUB_REPOSITORY", raising=False)
    assert cli.main(["--verify-release", "v1.0.0"]) == 1
    assert "VERIFY_RELEASE_FAILED" in capsys.readouterr().out


def test_cli_verify_uses_environment(monkeypatch) -> None:
    from cbp import cli
    monkeypatch.setenv("GITHUB_REPOSITORY", "owner/repo")
    monkeypatch.setattr(verify_release, "verify", lambda repository, tag, body, token: (True, "RELEASE_BODY_OK"))
    assert cli.main(["--verify-release", "v1.0.0"]) == 0
