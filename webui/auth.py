from __future__ import annotations

import logging
import secrets
import time
from collections import defaultdict, deque

from config import Settings
from store import Store, otp_digest

logger = logging.getLogger("cyberbutler.webui.auth")

SESSION_COOKIE = "cb_web_session"


class RateLimited(Exception):
    def __init__(self, retry_after: int = 60):
        self.retry_after = retry_after
        super().__init__("rate limited")


class InvalidCode(Exception):
    pass


class MailerFailed(Exception):
    pass


class RateLimiter:
    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def allow(self, key: str, limit: int, window: int) -> bool:
        now = time.monotonic()
        bucket = self._hits[key]
        while bucket and now - bucket[0] > window:
            bucket.popleft()
        if len(bucket) >= limit:
            return False
        bucket.append(now)
        return True

    def cooldown(self, key: str, seconds: int) -> bool:
        now = time.monotonic()
        bucket = self._hits["cooldown:" + key]
        while bucket and now - bucket[0] > seconds:
            bucket.popleft()
        if bucket:
            return False
        bucket.append(now)
        return True


class AuthService:
    def __init__(self, settings: Settings, store: Store, mailer) -> None:
        self.settings = settings
        self.store = store
        self.mailer = mailer
        self.limiter = RateLimiter()

    async def request_otp(self, email: str, ip: str) -> None:
        email = email.strip().lower()
        if not self.limiter.allow("otp-ip:" + ip, 10, 300):
            raise RateLimited(300)
        if email != self.settings.admin_email:
            return
        if not self.limiter.cooldown("otp-email:" + email, 60):
            raise RateLimited(60)
        if not self.limiter.allow("otp-email-window:" + email, 3, 300):
            raise RateLimited(300)

        code = f"{secrets.randbelow(1_000_000):06d}"
        salt = secrets.token_hex(16)
        self.store.create_otp(email, code, salt, self.settings.otp_ttl_seconds)
        try:
            await self.mailer.send(email, code, self.settings.otp_ttl_seconds)
        except Exception as exc:
            logger.error("OTP mail delivery failed: %s", exc)
            raise MailerFailed("verification mail could not be sent") from exc

    def verify(self, email: str, code: str, ip: str) -> tuple[str, str]:
        email = email.strip().lower()
        if not self.limiter.allow("verify-ip:" + ip, 20, 300):
            raise RateLimited(300)
        otp = self.store.latest_otp(email)
        if not otp:
            raise InvalidCode("no active code")
        now = int(time.time())
        if now > int(otp["expires_at"]) or int(otp["attempts"]) >= self.settings.otp_max_attempts:
            raise InvalidCode("code expired or locked")
        expected = otp_digest(self.settings.server_secret, email, code, otp["salt"])
        if not secrets.compare_digest(expected, otp["code_hash"]):
            attempts = self.store.bump_otp_attempts(otp["id"])
            if attempts >= self.settings.otp_max_attempts:
                raise InvalidCode("too many attempts")
            raise InvalidCode("incorrect code")
        self.store.use_otp(otp["id"])
        token = secrets.token_urlsafe(32)
        csrf = secrets.token_urlsafe(32)
        self.store.create_session(email, token, csrf, self.settings.session_days)
        return token, csrf

    def session(self, token: str | None) -> dict | None:
        if not token:
            return None
        return self.store.get_session(token, self.settings.idle_hours)

    def logout(self, token: str | None) -> None:
        if token:
            self.store.delete_session(token)
