from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "quality" / "quality_matrix.json"


def test_q01_path_boundaries_and_unicode():
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import win_path_guard
    except Exception as exc:
        pytest.skip(f"win_path_guard unavailable: {exc}")
    with pytest.raises(Exception):
        win_path_guard._reject_unsafe_path_text("C:/tmp/bad\x00name")
    with pytest.raises(Exception):
        win_path_guard._reject_unsafe_path_text("C:/tmp/bad\nname")
    # Emoji and long paths must not crash the parser. They may be accepted or
    # rejected, but they must return/raise a normal exception, not abort.
    for value in ("C:/tmp/\U0001F600.txt", "C:/tmp/" + "a" * 300 + ".txt"):
        try:
            win_path_guard._reject_unsafe_path_text(value)
        except Exception:
            pass


def test_q02_webui_hostile_input(tmp_path):
    webui = ROOT / "webui"
    sys.path.insert(0, str(webui))
    from fastapi.testclient import TestClient
    from app import create_app
    from settings import Settings

    class FakeMailer:
        async def send(self, email, code, ttl, lang="zh"):
            return None

    settings = Settings(admin_email="owner@example.com", data_dir=tmp_path / "data")
    settings.ensure_data()
    client = TestClient(create_app(settings, FakeMailer()))
    for payload in [
        {"email": "owner@example.com<script>alert(1)</script>"},
        {"email": "x' OR '1'='1@example.com"},
    ]:
        response = client.post("/api/auth/request-otp", json=payload)
        assert response.status_code == 200
        assert "<script>" not in response.text
        assert "OR '1'='1" not in response.text
    response = client.post("/api/auth/request-otp", json={"email": "a" * 5000 + "@example.com"})
    assert response.status_code in {400, 422}
    response = client.post("/api/auth/request-otp", content=b'{"email":' + b'x' * 2000000 + b'}', headers={"Content-Type": "application/json"})
    assert response.status_code in {400, 413, 422}


def test_q03_totp_replay_and_concurrency():
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import broker
        import pyotp
    except Exception as exc:
        pytest.skip(f"broker/pyotp unavailable: {exc}")
    secret = pyotp.random_base32()
    code = pyotp.TOTP(secret).now()
    old_secret = broker.secret
    broker.secret = lambda: secret
    try:
        with broker.broker_state._replay_lock:
            broker.broker_state._used_totp.clear()
        assert broker.verify_code(code) == "totp"
        assert broker.verify_code(code) == "replay"
        results = []
        with broker.broker_state._replay_lock:
            broker.broker_state._used_totp.clear()

        def worker():
            results.append(broker.verify_code(code))

        threads = [threading.Thread(target=worker) for _ in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        assert results.count("totp") == 1
    finally:
        broker.secret = old_secret


def test_q04_broker_config_tamper_fallback(tmp_path):
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import broker
    except Exception as exc:
        pytest.skip(f"broker unavailable: {exc}")
    old = broker.BROKER_CONFIG
    bad = tmp_path / "broker_config.json"
    bad.write_text("{not valid json", encoding="utf-8")
    broker.BROKER_CONFIG = bad
    try:
        assert broker._approval_channel() == "webui"
    finally:
        broker.BROKER_CONFIG = old


def _chaos(case: str) -> None:
    import os
    import tempfile
    root = os.environ.get("CBS_CHAOS_ROOT", r"C:\CyberButler")
    with tempfile.TemporaryDirectory(prefix="cbs-chaos-result-") as directory:
        result = Path(directory) / (case + ".json")
        command = [
            "pwsh.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(ROOT / "quality" / "run-chaos-harness.ps1"),
            "-Case", case, "-InstallRoot", root,
            "-ResultPath", str(result), "-ConfirmDestructive",
        ]
        completed = subprocess.run(command, capture_output=True, text=True, timeout=900)
        assert result.is_file(), completed.stdout + completed.stderr
        payload = json.loads(result.read_text(encoding="utf-8"))
        assert payload.get("status") == "passed", payload.get("detail")


def test_q05_broker_death_agent_unavailable():
    _chaos("Q05")


def test_q06_wfp_heartbeat_45_seconds():
    _chaos("Q06")


def test_q07_disk_full_capacity_breaker():
    _chaos("Q07")


def test_q08_service_acl_loss():
    _chaos("Q08")


def test_q09_1000_request_handle_leak():
    _chaos("Q09")


def test_q10_one_hour_memory_soak():
    _chaos("Q10")


def test_q11_orphan_process_scan():
    _chaos("Q11")


def test_q13_trash_acl_bypass():
    _chaos("Q13")


def test_q14_service_privilege_escalation():
    _chaos("Q14")


def test_q15_clean_uninstall_residue():
    _chaos("Q15")


def test_q16_offline_wheelhouse_python_free():
    _chaos("Q16")


def test_q17_interrupted_install_resume():
    _chaos("Q17")


def test_q18_no_unresolved_placeholders():
    package = next((p for p in [ROOT.parent / "public-release-v1.6.4-candidate.zip", ROOT.parent / "public-release-v1.6.4.zip"] if p.is_file()), ROOT.parent / "public-release-v1.6.4-candidate.zip")
    allowed = ("installer/", "tools/", "docs/", "tests/", "README-INSTALL.md", "DEPLOYMENT.md", "config.pro.example.json")
    if package.is_file():
        with zipfile.ZipFile(package) as archive:
            entries = [(name, archive.read(name)) for name in archive.namelist()]
    else:
        entries = [(path.relative_to(ROOT).as_posix(), path.read_bytes()) for path in (ROOT / "webui").rglob("*") if path.is_file() and not any(part in {".venv", "__pycache__"} for part in path.parts)]
    bad = [name for name, data in entries if not name.startswith(allowed) and b"YOUR_" in data]
    assert bad == []


def test_q19_qr_uri_matches_broker_secret():
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import broker
        import pyotp
    except Exception as exc:
        pytest.skip(f"broker/pyotp/qrcode unavailable: {exc}")
    secret = pyotp.random_base32()
    old = broker.secret
    broker.secret = lambda: secret
    try:
        payload = broker.totp_binding_payload()
        parsed = pyotp.parse_uri(payload["otpauth_uri"])
        assert parsed.secret == secret
        assert payload["qr_png_base64"]
    finally:
        broker.secret = old


def test_q20_version_single_source():
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    assert version == "1.6.4"
    template = (ROOT / "webui" / "templates" / "dashboard.html").read_text(encoding="utf-8")
    assert "v1.6.2" not in template


def test_q21_log_newline_injection(tmp_path, monkeypatch):
    monkeypatch.setenv("CBS_AUDIT_HMAC_KEY", "00" * 32)
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import audit_chain
    except Exception as exc:
        pytest.skip(f"audit_chain unavailable: {exc}")
    log = tmp_path / "audit.jsonl"
    audit_chain.append_event(log, {"file": "evil\n{\"forged\": true}", "ok": True})
    lines = log.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1
    payload = json.loads(lines[0])
    event = payload.get("event", payload)
    assert event.get("file", "").startswith("evil")


def test_q22_port_conflict_preflight():
    import socket
    listeners = []
    try:
        for port in (28090, 28765):
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("127.0.0.1", port))
            sock.listen(1)
            listeners.append(sock)
        probe = ROOT / "quality" / "port_conflict_probe.ps1"
        result = subprocess.run(
            ["pwsh.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(probe), "-Root", str(ROOT)],
            capture_output=True, text=True, timeout=45,
        )
        assert result.returncode == 0, result.stderr
        rows = json.loads(result.stdout.strip() or "[]")
        if isinstance(rows, dict):
            rows = [rows]
        states = {int(row["port"]): bool(row.get("in_use")) for row in rows}
        assert states.get(28090) is True
        assert states.get(28765) is True
    finally:
        for sock in listeners:
            sock.close()


def test_q23_audit_chain_detects_tamper(tmp_path, monkeypatch):
    monkeypatch.setenv("CBS_AUDIT_HMAC_KEY", "00" * 32)
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import audit_chain
    except Exception as exc:
        pytest.skip(f"audit_chain unavailable: {exc}")
    log = tmp_path / "audit.jsonl"
    audit_chain.append_event(log, {"event": "one"})
    audit_chain.append_event(log, {"event": "two"})
    assert audit_chain.verify_chain(log)[0] is True
    lines = log.read_text(encoding="utf-8").splitlines()
    lines[0] = lines[0].replace("one", "tampered")
    log.write_text("\n".join(lines) + "\n", encoding="utf-8")
    assert audit_chain.verify_chain(log)[0] is False


def test_q24_package_has_no_dev_artifacts():
    package = next((p for p in [ROOT.parent / "public-release-v1.6.4-candidate.zip", ROOT.parent / "public-release-v1.6.4.zip"] if p.is_file()), ROOT.parent / "public-release-v1.6.4-candidate.zip")
    assert package.is_file(), "release zip not built"
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
    forbidden = [
        name for name in names
        if ".venv/" in name
        or name.startswith("tmp-")
        or name.startswith("YOUR_PROJECT_PATH/")
        or name.endswith("pytest.ini")
        or "/__pycache__/" in name
    ]
    assert forbidden == []


def test_q25_matrix_has_25_items():
    data = json.loads(MATRIX.read_text(encoding="utf-8"))
    assert len(data["items"]) == 26
    assert len({item["id"] for item in data["items"]}) == 26


def test_q26_sbom_matches_actual_package():
    import hashlib

    package = next((p for p in [ROOT.parent / "public-release-v1.6.4-candidate.zip", ROOT.parent / "public-release-v1.6.4.zip"] if p.is_file()), ROOT.parent / "public-release-v1.6.4-candidate.zip")
    assert package.is_file(), "release zip not built"
    with zipfile.ZipFile(package) as archive:
        manifest = json.loads(archive.read("dependencies.sbom.json").decode("utf-8"))
        for entry in manifest.get("entries", []):
            path = str(entry.get("path", ""))
            data = archive.read(path)
            assert hashlib.sha256(data).hexdigest() == entry.get("sha256"), path
            requirements = [
                line.strip() for line in data.decode("utf-8").splitlines()
                if line.strip() and not line.lstrip().startswith("#")
            ]
            assert requirements == entry.get("requirements"), path
