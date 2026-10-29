from __future__ import annotations

import hashlib
import hmac
import sqlite3
import time
from pathlib import Path


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def otp_digest(secret: bytes, email: str, code: str, salt: str) -> str:
    message = f"{email.lower()}|{code}|{salt}".encode("utf-8")
    return hmac.new(secret, message, hashlib.sha256).hexdigest()


class Store:
    def __init__(self, path: Path, secret: bytes):
        self.path = Path(path)
        self.secret = secret
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.init()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=10)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        return conn

    def init(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS otps (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL,
                    code_hash TEXT NOT NULL,
                    salt TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    expires_at INTEGER NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    used INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_otps_email ON otps(email, used, id);
                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash TEXT PRIMARY KEY,
                    email TEXT NOT NULL,
                    csrf TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    last_seen INTEGER NOT NULL,
                    expires_at INTEGER NOT NULL
                );
                """
            )

    def create_otp(self, email: str, code: str, salt: str, ttl: int) -> None:
        now = int(time.time())
        digest = otp_digest(self.secret, email, code, salt)
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO otps(email, code_hash, salt, created_at, expires_at) VALUES (?,?,?,?,?)",
                (email.lower(), digest, salt, now, now + ttl),
            )

    def latest_otp(self, email: str) -> dict | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM otps WHERE email=? AND used=0 ORDER BY id DESC LIMIT 1",
                (email.lower(),),
            ).fetchone()
        return dict(row) if row else None

    def bump_otp_attempts(self, otp_id: int) -> int:
        with self._connect() as conn:
            conn.execute("UPDATE otps SET attempts=attempts+1 WHERE id=?", (otp_id,))
            row = conn.execute("SELECT attempts FROM otps WHERE id=?", (otp_id,)).fetchone()
        return int(row["attempts"]) if row else 0

    def use_otp(self, otp_id: int) -> None:
        with self._connect() as conn:
            conn.execute("UPDATE otps SET used=1 WHERE id=?", (otp_id,))

    def create_session(self, email: str, token: str, csrf: str, days: int) -> None:
        now = int(time.time())
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO sessions(token_hash,email,csrf,created_at,last_seen,expires_at) VALUES (?,?,?,?,?,?)",
                (sha256_hex(token), email.lower(), csrf, now, now, now + days * 86400),
            )

    def get_session(self, token: str, idle_hours: int) -> dict | None:
        now = int(time.time())
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM sessions WHERE token_hash=?", (sha256_hex(token),)
            ).fetchone()
            if not row:
                return None
            data = dict(row)
            if now > int(data["expires_at"]) or now - int(data["last_seen"]) > idle_hours * 3600:
                conn.execute("DELETE FROM sessions WHERE token_hash=?", (data["token_hash"],))
                return None
            conn.execute(
                "UPDATE sessions SET last_seen=? WHERE token_hash=?",
                (now, data["token_hash"]),
            )
            data["last_seen"] = now
            return data

    def delete_session(self, token: str) -> None:
        with self._connect() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash=?", (sha256_hex(token),))

    def purge_expired(self) -> None:
        now = int(time.time())
        with self._connect() as conn:
            conn.execute("DELETE FROM otps WHERE expires_at<? OR used=1", (now - 3600,))
            conn.execute("DELETE FROM sessions WHERE expires_at<?", (now,))
