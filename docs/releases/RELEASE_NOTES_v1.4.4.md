# v1.4.4 — Complete Web UI i18n (8 languages)

## Added

- Eight local locale packs, matching the README and the WPF dictionary exactly:
  `zh, en, ja, ko, es, fr, de, ru`.
- 162 Web UI keys per locale, with a zero-missing key-set test and fallback to
  Chinese for any future missing key.
- Language selector on the login page *before* OTP sending, and on the
  dashboard; choice stored in `localStorage("cb-lang")`.
- First-run detection: saved language > browser language prefix > Chinese.
  `zh-CN`, `zh-TW`, `zh-Hans` and `zh-Hant` map to `zh`.
- OTP email language follows the login selector: the request sends `lang`, the
  mailer loads `email.subject` / `email.body` from the same locale JSON, and an
  invalid language falls back to `zh`.
- Dynamic re-render on language change without a page reload: temperatures,
  token/cost, service states, plugins, logs, backups, approval banner, chat
  status, file list and existing file preview metadata. The active tab and
  session are preserved.
- Stable backend `code` fields for auth/service/chat/files errors, while the
  existing Chinese `message` remains as fallback. The front-end shows a
  translated code when known, otherwise the Chinese message.
- Localized 403/404/500 error page. It never includes the path, stack, SQL,
  filesystem or internal exception details.
- CSP tightened: no `unsafe-inline` or `unsafe-eval`; locale packs are local
  static JSON, no CDN.
- Mobile and long-text CSS for the language selector, buttons, cards, chat and
  file manager; verified at 390, 768 and 1440 px.

## Security

- No new write/delete/upload/rename/restore/approval/configuration API.
- File sandbox root lock, resolve checks, extension blocking and 20MB limit are
  unchanged.
- SMTP secret handling is unchanged: only the standalone mailer reads the DPAPI
  secret.
- Tailscale/firewall rules are unchanged.

## Verified

```text
webui pytest                 22 passed
release pytest               43 passed
i18n key parity              8/8, missing 0
login / dashboard / files / chat / banner in zh/en/de/ru   no empty text,
                              no key leaks, no horizontal overflow
login 390/768/1440           no overflow (ru)
error 404 (de)               localized, no path
OTP mail lang=de             sent through localized mailer
CSP                          no unsafe-inline / unsafe-eval
```
