from __future__ import annotations

import json
import re
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
I18N = BASE / "static" / "i18n"
LANGS = ["zh", "en", "ja", "ko", "es", "fr", "de", "ru"]


def load(lang: str) -> dict:
    return json.loads((I18N / f"{lang}.json").read_text(encoding="utf-8"))


def test_eight_locales_have_identical_keys_and_no_missing_values() -> None:
    data = {lang: load(lang)["strings"] for lang in LANGS}
    keys = set(data["zh"])
    assert keys
    for lang in LANGS:
        assert set(data[lang]) == keys, f"key mismatch in {lang}"
        assert all(str(value).strip() for value in data[lang].values()), f"empty value in {lang}"
    for key in keys:
        assert data["zh"].get(key), key


def test_placeholders_match_chinese_fallback() -> None:
    data = {lang: load(lang)["strings"] for lang in LANGS}
    for key, zh_value in data["zh"].items():
        expected = set(re.findall(r"\{[A-Za-z0-9_]+\}", zh_value))
        for lang in LANGS[1:]:
            actual = set(re.findall(r"\{[A-Za-z0-9_]+\}", data[lang][key]))
            assert actual == expected, f"placeholder mismatch: {lang} {key}"


def test_email_templates_and_language_codes() -> None:
    for lang in LANGS:
        payload = load(lang)
        assert payload["code"] == lang
        assert "email.subject" in payload["strings"]
        assert "email.body" in payload["strings"]
        assert "{code}" in payload["strings"]["email.body"]


def test_templates_do_not_use_inline_translations_or_csp_unsafe_inline() -> None:
    templates = "\n".join(
        (BASE / "templates" / name).read_text(encoding="utf-8")
        for name in ("login.html", "dashboard.html", "error.html")
    )
    # Native language names are the only allowed Chinese literals in markup.
    assert "登录控制台" not in templates
    assert "我的大肥鱼文件" not in templates
    assert "有高风险操作等待审批" not in templates
    app = (BASE / "app.py").read_text(encoding="utf-8")
    assert "style-src 'self' 'unsafe-inline'" not in app
    assert "script-src 'self' 'unsafe-eval'" not in app


def test_all_template_i18n_keys_exist() -> None:
    keys = set(load("zh")["strings"])
    for name in ("login.html", "dashboard.html", "error.html"):
        text = (BASE / "templates" / name).read_text(encoding="utf-8")
        used = set(re.findall(r'data-i18n(?:-placeholder|-aria-label|-title)?="([^"]+)"', text))
        missing = sorted(key for key in used if key not in keys)
        assert not missing, f"{name} missing keys: {missing}"


def test_email_templates_cover_all_languages() -> None:
    from otp_mailer import load_email_strings
    for lang in LANGS:
        strings = load_email_strings(lang)
        assert strings.get("email.subject")
        body = strings.get("email.body", "")
        assert "{code}" in body
        assert "{minutes}" in body
