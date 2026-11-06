#!/usr/bin/env python3
"""Download the hash lock once, then install it with --no-index."""
from __future__ import annotations

import subprocess
import sys
import tempfile
import venv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "requirements-runtime.lock"


def main() -> int:
    if not LOCK.is_file():
        print("OFFLINE_HASH_FAILED: lock missing")
        return 1
    with tempfile.TemporaryDirectory(prefix="cbp-offline-") as temp:
        root = Path(temp)
        wheels = root / "wheelhouse"
        wheels.mkdir()
        download = subprocess.run([sys.executable, "-m", "pip", "download", "--require-hashes", "-r", str(LOCK), "-d", str(wheels)])
        if download.returncode != 0:
            print("OFFLINE_HASH_FAILED: pip download failed")
            return 1
        target = root / "venv"
        venv.EnvBuilder(with_pip=True).create(target)
        python = target / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
        install = subprocess.run([str(python), "-m", "pip", "install", "--no-index", "--find-links", str(wheels), "--require-hashes", "-r", str(LOCK)])
        if install.returncode != 0:
            print("OFFLINE_HASH_FAILED: offline install failed")
            return 1
        check = subprocess.run([str(python), "-c", "import requests, certifi; print('OFFLINE_HASH_OK')"], capture_output=True, text=True)
        print(check.stdout.strip())
        return 0 if check.returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
