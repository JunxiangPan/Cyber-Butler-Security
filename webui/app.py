from __future__ import annotations

import logging
import secrets
import time
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from starlette.exceptions import HTTPException as StarletteHTTPException
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field

from auth import AuthService, InvalidCode, MailerFailed, RateLimited, RateLimiter, SESSION_COOKIE
from settings import Settings
from mailer import MailerClient
from file_manager import FileAccessError, FileManager
from services import ServiceError, WebServices
from store import Store

BASE_DIR = Path(__file__).resolve().parent
SUPPORTED_LANGS = {"zh", "en", "ja", "ko", "es", "fr", "de", "ru"}
logger = logging.getLogger("cyberbutler.webui")


class EmailRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    lang: str | None = Field(default=None, max_length=16)


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
    files = FileManager(settings)

    app = FastAPI(title="Cyber-Butler Web", docs_url=None, redoc_url=None, openapi_url=None)
    app.state.settings = settings
    app.state.auth = auth
    app.state.mailer = mailer
    app.state.services = services
    app.state.files = files
    app.state.chat_limiter = RateLimiter()
    app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")
    templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

    def api_error(detail, status_code: int) -> JSONResponse:
        if isinstance(detail, dict):
            code = str(detail.get("code") or "http.error")
            message = str(detail.get("message") or "request failed")
        else:
            code = "http.error"
            message = "request failed"
        return JSONResponse({"ok": False, "code": code, "message": message}, status_code=status_code)

    @app.exception_handler(StarletteHTTPException)
    async def http_error_page(request: Request, exc: StarletteHTTPException):
        if request.url.path.startswith("/api/"):
            return api_error(exc.detail, exc.status_code)
        if exc.status_code in (403, 404):
            return templates.TemplateResponse(
                request, "error.html", {"status": str(exc.status_code)}, status_code=exc.status_code
            )
        return templates.TemplateResponse(request, "error.html", {"status": "500"}, status_code=500)

    @app.exception_handler(Exception)
    async def internal_error_page(request: Request, exc: Exception):
        logger.exception("unhandled Web UI error: %s", exc)
        if request.url.path.startswith("/api/"):
            return JSONResponse({"ok": False, "code": "http.error", "message": "request failed"}, status_code=500)
        return templates.TemplateResponse(request, "error.html", {"status": "500"}, status_code=500)

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        response.headers.setdefault(
            "Content-Security-Policy",
            "default-src 'self'; style-src 'self'; script-src 'self'; "
            "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
        )
        if request.url.path.startswith("/api/auth/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    def cookie_secure(request: Request) -> bool:
        if settings.cookie_secure == "auto":
            if request.url.scheme == "https":
                return True
            forwarded = request.headers.get("x-forwarded-proto", "").split(",")[0].strip().lower()
            client = request.client.host if request.client else ""
            return forwarded == "https" and client in {"127.0.0.1", "::1"}
        return bool(settings.cookie_secure)

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
        return {"ok": True, "phase": 2}

    @app.post("/api/auth/request-otp")
    async def request_otp(body: EmailRequest, request: Request):
        ip = request.client.host if request.client else "unknown"
        try:
            lang = body.lang if body.lang in SUPPORTED_LANGS else "zh"
            await auth.request_otp(body.email, ip, lang)
        except RateLimited as exc:
            return JSONResponse(
                {"ok": False, "code": "auth.rate_limited", "message": "请求过于频繁，请稍后再试。", "retry_after": exc.retry_after},
                status_code=429,
            )
        except MailerFailed:
            return JSONResponse(
                {"ok": False, "code": "auth.mailer_failed", "message": "验证码发送失败，请稍后重试。"}, status_code=503
            )
        return {
            "ok": True,
            "code": "auth.otp_sent",
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
                {"ok": False, "code": "auth.rate_limited", "message": "尝试过于频繁，请稍后再试。", "retry_after": exc.retry_after},
                status_code=429,
            )
        except InvalidCode:
            return JSONResponse({"ok": False, "code": "auth.invalid_code", "message": "验证码不正确或已过期。"}, status_code=401)

        response.set_cookie(
            key=SESSION_COOKIE,
            value=token,
            max_age=settings.session_seconds,
            httponly=True,
            secure=cookie_secure(request),
            samesite="strict",
            path="/",
        )
        return {"ok": True, "code": "auth.ok", "email": body.email.strip().lower(), "csrf": csrf}

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
            return JSONResponse({"ok": False, "code": "auth.csrf_invalid", "message": "invalid csrf token"}, status_code=403)
        auth.logout(request.cookies.get(SESSION_COOKIE))
        response.delete_cookie(SESSION_COOKIE, path="/", samesite="strict", secure=cookie_secure(request))
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
            return JSONResponse({"ok": False, "code": "service.status_failed", "message": "状态读取失败。"}, status_code=502)

    @app.get("/api/temps")
    async def temps(session=Depends(require_session)):
        try:
            return await services.temperatures()
        except ServiceError as exc:
            logger.warning("temperature read failed: %s", exc)
            return JSONResponse({"ok": False, "code": "service.temps_failed", "message": "温度读取失败。"}, status_code=502)

    @app.get("/api/astrbot/plugins")
    async def astrbot_plugins(session=Depends(require_session)):
        try:
            return await services.astrbot_plugins()
        except ServiceError as exc:
            logger.warning("plugin list failed: %s", exc)
            return JSONResponse({"ok": False, "code": "service.plugins_failed", "message": "插件列表读取失败。"}, status_code=502)

    @app.get("/api/logs")
    async def logs(name: str = "astrbot", lines: int = 80, session=Depends(require_session)):
        if name not in {"astrbot", "broker", "dashboard", "snowluma"}:
            return JSONResponse({"ok": False, "code": "logs.unknown", "message": "unknown log name"}, status_code=400)
        try:
            return services.logs(name, max(1, min(int(lines), 200)))
        except ServiceError as exc:
            logger.warning("log read failed: %s", exc)
            return JSONResponse({"ok": False, "code": "service.logs_failed", "message": "日志读取失败。"}, status_code=502)

    def audit_file_denial(request: Request, relative: str, reason: str) -> None:
        safe = str(relative or "")[:160]
        logger.warning("[files] denied reason=%s path=%r", reason, safe)
        try:
            path = settings.data_dir / "files-audit.log"
            with path.open("a", encoding="utf-8") as handle:
                print(f"{int(time.time())} ip={request.client.host if request.client else 'unknown'} reason={reason} path={safe!r}", file=handle)
        except OSError:
            pass

    @app.get("/api/usage")
    async def usage(session=Depends(require_session)):
        try:
            return await services.usage()
        except ServiceError as exc:
            logger.warning("usage read failed: %s", exc)
            return JSONResponse({"ok": False, "code": "service.usage_failed", "message": "用量统计读取失败。"}, status_code=502)

    @app.get("/api/backups")
    async def backups(session=Depends(require_session)):
        try:
            return services.backups()
        except Exception as exc:
            logger.warning("backup list failed: %s", exc)
            return JSONResponse({"ok": False, "code": "service.backups_failed", "message": "备份列表读取失败。"}, status_code=502)

    @app.get("/api/security/pending")
    async def security_pending(session=Depends(require_session)):
        return await services.security_pending()

    def file_error_code(exc: Exception) -> str:
        message = str(exc).lower()
        if "exceeds the download limit" in message:
            return "files.too_large"
        if "file type is blocked" in message:
            return "files.blocked"
        if "path not found" in message:
            return "files.not_found"
        return "files.denied"

    @app.get("/api/files/list")
    async def files_list(request: Request, path: str = "", session=Depends(require_session)):
        try:
            return files.list_dir(path)
        except FileAccessError as exc:
            audit_file_denial(request, path, str(exc))
            return JSONResponse({"ok": False, "code": file_error_code(exc), "message": "file access denied"}, status_code=403)
        except Exception as exc:
            audit_file_denial(request, path, "unexpected")
            logger.warning("file list failed: %s", exc)
            return JSONResponse({"ok": False, "code": file_error_code(exc), "message": "file access denied"}, status_code=403)

    @app.get("/api/files/download")
    async def files_download(request: Request, path: str, download: bool = False, session=Depends(require_session)):
        try:
            info = files.file_info(path)
        except FileAccessError as exc:
            audit_file_denial(request, path, str(exc))
            return JSONResponse({"ok": False, "code": file_error_code(exc), "message": "file access denied"}, status_code=403)
        except Exception as exc:
            audit_file_denial(request, path, "unexpected")
            logger.warning("file download failed: %s", exc)
            return JSONResponse({"ok": False, "code": file_error_code(exc), "message": "file access denied"}, status_code=403)
        inline = (not download) and info["category"] in {"image", "text", "pdf"}
        return FileResponse(
            path=info["target"],
            media_type=info["media_type"],
            filename=info["name"],
            content_disposition_type="inline" if inline else "attachment",
            headers={"X-Content-Type-Options": "nosniff", "Cache-Control": "no-store"},
        )

    @app.post("/api/chat/send")
    async def chat_send(body: ChatRequest, request: Request, session=Depends(require_session)):
        provided = request.headers.get("X-CSRF-Token", "")
        if not secrets.compare_digest(provided, session["csrf"]):
            return JSONResponse({"ok": False, "code": "auth.csrf_invalid", "message": "invalid csrf token"}, status_code=403)
        ip = request.client.host if request.client else "unknown"
        if not app.state.chat_limiter.allow("chat:" + ip, 5, 60):
            return JSONResponse(
                {"ok": False, "code": "chat.rate_limited", "message": "发送过于频繁，请稍后再试。", "retry_after": 60},
                status_code=429,
            )
        text = body.message.strip()
        if not text:
            return JSONResponse({"ok": False, "code": "chat.empty", "message": "empty message"}, status_code=400)
        try:
            return await services.enqueue_chat(text)
        except ServiceError as exc:
            logger.warning("chat send failed: %s", exc)
            return JSONResponse({"ok": False, "code": "chat.failed", "message": "消息发送失败。"}, status_code=502)

    @app.get("/favicon.ico")
    async def favicon():
        return Response(status_code=204)

    return app
