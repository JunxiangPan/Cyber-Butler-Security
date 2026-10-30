"""Redaction and length limits for read-only log output."""

from __future__ import annotations

import re

_MAX_LOG_LINE = 300

_ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
_CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
_SECRET_KV_RE = re.compile(
    r"(?i)\b(token|api[_-]?key|secret|password|passwd|authorization|cookie|"
    r"totp|otp|验证码|密钥|口令)\b\s*[:=]\s*[^\s,;]+"
)
_BEARER_RE = re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+")
_BASIC_RE = re.compile(r"(?i)\bBasic\s+[A-Za-z0-9+/=]+")
_APIKEY_RE = re.compile(r"(?i)\bApiKey\s+[A-Za-z0-9._~+/=-]+")
_X_API_KEY_RE = re.compile(r"(?i)\bX-API-Key\s*:\s*[^\s,;]+")
_EMAIL_RE = re.compile(r"(?<![\w.+-])[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}(?![\w.-])")
_PHONE_RE = re.compile(r"(?<!\d)1[3-9]\d{9}(?!\d)")
_OTP_RE = re.compile(r"(?i)\b(otp|totp|code|验证码)\b\s+\d{6}\b")
_ID_KV_RE = re.compile(r"(?i)\b(qq|uin|user_id|sender_id)\b\s*[:=]\s*\d{5,12}\b")
_URL_QUERY_RE = re.compile(r"(https?://[^\s?#]+)\?[^\s]+")


def redact_line(line: str) -> str:
    """Remove ANSI/control characters and common secret/PII patterns.

    Args:
        line: One raw log line.

    Returns:
        A single-line, redacted string capped at 300 characters.
    """
    text = _ANSI_RE.sub("", str(line))
    text = _CONTROL_RE.sub("", text).replace("\r", "").replace("\n", " ")
    text = _BEARER_RE.sub("Bearer [REDACTED]", text)
    text = _BASIC_RE.sub("Basic [REDACTED]", text)
    text = _APIKEY_RE.sub("ApiKey [REDACTED]", text)
    text = _X_API_KEY_RE.sub("X-API-Key: [REDACTED]", text)
    text = _SECRET_KV_RE.sub(lambda match: f"{match.group(1)}=[REDACTED]", text)
    text = _EMAIL_RE.sub("[EMAIL]", text)
    text = _PHONE_RE.sub("[PHONE]", text)
    text = _OTP_RE.sub(lambda match: f"{match.group(1)} [REDACTED]", text)
    text = _ID_KV_RE.sub(lambda match: f"{match.group(1)}=[REDACTED]", text)
    text = _URL_QUERY_RE.sub(lambda match: f"{match.group(1)}?[REDACTED]", text)
    text = " ".join(text.split())
    if len(text) > _MAX_LOG_LINE:
        text = text[: _MAX_LOG_LINE - 1].rstrip() + "…"
    return text


def truncate_text(text: str, limit: int) -> str:
    """Cap a multi-line reply and mark truncation.

    Args:
        text: Rendered reply.
        limit: Maximum character count.

    Returns:
        The original text, or a prefix plus a truncation marker.
    """
    value = str(text)
    if len(value) <= limit:
        return value
    marker = "\n[truncated]"
    return value[: max(0, limit - len(marker))].rstrip() + marker
