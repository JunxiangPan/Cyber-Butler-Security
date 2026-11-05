from __future__ import annotations

import httpx


class MailerClient:
    """MailerClient helper/type."""
    def __init__(self, url: str, token: str, timeout: float = 10) -> None:
        """Init.
        
        Args:
            url: caller-supplied value.
            token: caller-supplied value.
            timeout: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        self.url = url
        self.token = token
        self.timeout = timeout

    async def send(self, email: str, code: str, ttl: int, lang: str = "zh") -> None:
        """Send.
        
        Args:
            email: caller-supplied value.
            code: caller-supplied value.
            ttl: caller-supplied value.
            lang: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                self.url,
                json={"email": email, "code": code, "ttl": ttl, "lang": lang},
                headers={"Authorization": f"Bearer {self.token}"},
            )
        if response.status_code != 200:
            raise RuntimeError(f"otp mailer returned HTTP {response.status_code}")
