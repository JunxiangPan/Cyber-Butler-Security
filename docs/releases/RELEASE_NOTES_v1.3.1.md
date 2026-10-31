# v1.3.1 — Eight-language dashboard

## Added

- `dashboard_i18n.json` now carries **eight complete dictionaries** for all
  117 entries: `zh`, `en`, `ja`, `ko`, `es`, `fr`, `de`, `ru`.
- Settings → Language lists all eight native names (中文 / English / 日本語 /
  한국어 / Español / Français / Deutsch / Русский) with language tags.
- Selecting a language applies it immediately (`Apply-Language`), re-renders
  the plugin/module/persona lists and dynamic counters, and persists the code
  (`zh|en|ja|ko|es|fr|de|ru`) in `dashboard-settings.json`.
- `T()` now resolves through the full dictionary for the active language, with
  an English fallback for dynamic strings that are not dictionary entries.

## Font fallback

- Both the main window and the settings window declare
  `FontFamily="Microsoft YaHei UI, Segoe UI, Yu Gothic UI, Malgun Gothic"`.
  Cyrillic, Japanese and Korean glyphs render through the fallback chain; the
  Russian, French and Japanese screenshots show no tofu boxes.
- Persona action buttons use `MinWidth` + padding instead of fixed widths, so
  longer Russian/French labels are no longer clipped.

## Verified

```text
pytest: 39 passed
privacy scan: OK
UI screenshots: ja / ru / fr (Persona & Memory, Agent Plugins)
Fonts: Cyrillic + Japanese rendered, no missing-glyph boxes
Modules: 3 loaded (Hello World, Live Monitor, Quick Cmd)
```

## Notes

- Conversation/persona content remains in its original language; only the
  dashboard chrome is translated.
- Dynamic counters use dictionary templates where available and English
  fallback otherwise, so no Chinese leaks into non-Chinese UI.
