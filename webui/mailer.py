from __future__ import annotations

import httpx


class MailerClient:
    def __init__(self, url: str, token: str, timeout: float = 10) -> None:
        self.url = url
        self.token = token
        self.timeout = timeout

    async def send(self, email: str, code: str, ttl: int) -> None:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                self.url,
                json={"email": email, "code": code, "ttl": ttl},
                headers={"Authorization": f"Bearer {self.token}"},
            )
        if response.status_code != 200:
            raise RuntimeError(f"otp mailer returned HTTP {response.status_code}")
