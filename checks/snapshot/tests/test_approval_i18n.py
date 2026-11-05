"""Approval prompts must be localized and role-free."""
from __future__ import annotations

import approval_i18n


def test_all_supported_languages_have_technical_header(monkeypatch) -> None:
    for language in approval_i18n.TRANSLATIONS:
        monkeypatch.setenv("CBS_APPROVAL_LANGUAGE", language)
        header = approval_i18n.t("header")
        assert header
        assert "persona" not in header.casefold()
        assert "roleplay" not in header.casefold()


def test_manifest_prompt_formats_count(monkeypatch) -> None:
    monkeypatch.setenv("CBS_APPROVAL_LANGUAGE", "en")
    assert "3" in approval_i18n.t("manifest", count=3)


def test_unknown_language_falls_back_to_english(monkeypatch) -> None:
    monkeypatch.setenv("CBS_APPROVAL_LANGUAGE", "xx")
    assert approval_i18n.t("header") == approval_i18n.TRANSLATIONS["en"]["header"]
