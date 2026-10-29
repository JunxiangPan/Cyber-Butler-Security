from __future__ import annotations

import logging
import secrets
import time
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field

from auth import AuthService, InvalidCode, MailerFailed, RateLimited, RateLimiter, SESSION_COOKIE
from settings import Settings
from mailer import MailerClient
from services import ServiceError, WebServices
from store import Store

BASE_DIR = Path(__file__).resolve().parent
logger = logging.getLogger("cyberbutler.webui")


class EmailRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)


class VerifyRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    code: str = Field(min_length=6, max_length=6)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=500)


def create_app(settings: Settings | None = None, mailer=None, services=None) -> FastAPI:
    settings = settings or Settings.load()
    store = Store(settings.db_path, settings.server_secret)
    mailer = mailer or MailerClient(settings.mailer_url, settings.mailer_token)
    auth = AuthService(settings, store, mailer)
    services = services or WebServices(settings)

    app = FastAPI(title="Cyber-Butler Web", docs_url=None, redoc_url=None, openapi_url=None)
    app.state.settings = settings
    app.state.auth = auth
    app.state.mailer = mailer
    app.state.services = services
    app.state.chat_limiter = RateLimiter()
    app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")
    templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        response.headers.setdefault(
            "Content-Security-Policy",
            "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; "
            "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
        )
        if request.url.path.startswith("/api/auth/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    def current_session(request: Request) -> dict | None:
        return auth.session(request.cookies.get(SESSION_COOKIE))

    def require_session(request: Request) -> dict:
        session = current_session(request)
        if not session:
            raise HTTPException(status_code=401, detail="authentication required")
        return session

    @app.get("/", response_class=HTMLResponse)
    async def index(request: Request):
        session = current_session(request)
        if session:
            return templates.TemplateResponse(
                request, "dashboard.html", {"email": session["email"], "phase": "2"}
            )
        return templates.TemplateResponse(request, "login.html", {"phase": "2"})

    @app.get("/api/health")
    async def health():
        return {"ok": True, "phase": 1}

    @app.post("/api/auth/request-otp")
    async def request_otp(body: EmailRequest, request: Request):
        ip = request.client.host if request.client else "unknown"
        try:
            await auth.request_otp(body.email, ip)
        except RateLimited as exc:
            return JSONResponse(
                {"ok": False, "message": "请求过于频繁，请稍后再试。", "retry_after": exc.retry_after},
                status_code=429,
            )
        except MailerFailed:
            return JSONResponse(
                {"ok": False, "message": "验证码发送失败，请稍后重试。"}, status_code=503
            )
        return {
            "ok": True,
            "message": "如果该邮箱已登记，验证码已发送。",
            "ttl": settings.otp_ttl_seconds,
        }

    @app.post("/api/auth/verify")
    async def verify(body: VerifyRequest, request: Request, response: Response):
        ip = request.client.host if request.client else "unknown"
        try:
            token, csrf = auth.verify(body.email, body.code, ip)
        except RateLimited as exc:
            return JSONResponse(
                {"ok": False, "message": "尝试过于频繁，请稍后再试。", "retry_after": exc.retry_after},
                status_code=429,
            )
        except InvalidCode as exc:
            return JSONResponse({"ok": False, "message": str(exc)}, status_code=401)

        response.set_cookie(
            key=SESSION_COOKIE,
            value=token,
            max_age=settings.session_seconds,
            httponly=True,
            secure=settings.cookie_secure,
            samesite="strict",
            path="/",
        )
        return {"ok": True, "email": body.email.strip().lower(), "csrf": csrf}

    @app.get("/api/auth/me")
    async def me(request: Request, session=Depends(require_session)):
        return {
            "ok": True,
            "email": session["email"],
            "csrf": session["csrf"],
            "expires_at": session["expires_at"],
        }

    @app.post("/api/auth/logout")
    async def logout(request: Request, response: Response, session=Depends(require_session)):
        provided = request.headers.get("X-CSRF-Token", "")
        if not secrets.compare_digest(provided, session["csrf"]):
            raise HTTPException(status_code=403, detail="invalid csrf token")
        auth.logout(request.cookies.get(SESSION_COOKIE))
        response.delete_cookie(SESSION_COOKIE, path="/")
        return {"ok": True}

    @app.get("/api/summary")
    async def summary(session=Depends(require_session)):
        return {
            "ok": True,
            "phase": 2,
            "email": session["email"],
            "server_time": int(time.time()),
            "capabilities": ["read-only", "email-otp-auth", "fixed-recipient-chat"],
        }

    @app.get("/api/status")
    async def status(session=Depends(require_session)):
        try:
            return await services.status()
        except ServiceError as exc:
            logger.warning("status failed: %s", exc)
            return JSONResponse({"ok": False, "message": "状态读取失败。"}, status_code=502)

    @app.get("/api/temps")
    async def temps(session=Depends(require_session)):
        try:
            return await services.temperatures()
        except ServiceError as exc:
            logger.warning("temperature read failed: %s", exc)
            return JSONResponse({"ok": False, "message": "温度读取失败。"}, status_code=502)

    @app.get("/api/astrbot/plugins")
    async def astrbot_plugins(session=Depends(require_session)):
        try:
            return await services.astrbot_plugins()
        except ServiceError as exc:
            logger.warning("plugin list failed: %s", exc)
            return JSONResponse({"ok": False, "message": "插件列表读取失败。"}, status_code=502)

    @app.get("/api/logs")
    async def logs(name: str = "astrbot", lines: int = 80, session=Depends(require_session)):
        if name not in {"astrbot", "broker", "dashboard", "snowluma"}:
            raise HTTPException(status_code=400, detail="unknown log name")
        try:
            return services.logs(name, max(1, min(int(lines), 200)))
        except ServiceError as exc:
            logger.warning("log read failed: %s", exc)
            return JSONResponse({"ok": False, "message": "日志读取失败。"}, status_code=502)

    @app.post("/api/chat/send")
    async def chat_send(body: ChatRequest, request: Request, session=Depends(require_session)):
        provided = request.headers.get("X-CSRF-Token", "")
        if not secrets.compare_digest(provided, session["csrf"]):
            raise HTTPException(status_code=403, detail="invalid csrf token")
        ip = request.client.host if request.client else "unknown"
        if not app.state.chat_limiter.allow("chat:" + ip, 5, 60):
            return JSONResponse(
                {"ok": False, "message": "发送过于频繁，请稍后再试。", "retry_after": 60},
                status_code=429,
            )
        text = body.message.strip()
        if not text:
            raise HTTPException(status_code=400, detail="empty message")
        try:
            return await services.enqueue_chat(text)
        except ServiceError as exc:
            logger.warning("chat send failed: %s", exc)
            return JSONResponse({"ok": False, "message": "消息发送失败。"}, status_code=502)

    @app.get("/favicon.ico")
    async def favicon():
        return Response(status_code=204)

    return app
