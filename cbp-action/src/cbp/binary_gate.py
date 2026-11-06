"""Generic large-binary provenance gate."""
from __future__ import annotations

import hashlib
import json
import zipfile
from pathlib import Path

from .config import GateConfig

SUFFIXES = {".exe", ".dll", ".bin"}
SUPPORTED_SCOPES = {"self-contained-runtime", "runtime-pack", "runtime-only"}


def info_size(archive, name):
    """Return a ZIP member's uncompressed size."""
    return archive.getinfo(name).file_size


def _candidates(cfg: GateConfig):
    package = cfg.path(cfg.package_zip) if cfg.package_zip else None
    if package and package.is_file():
        with zipfile.ZipFile(package) as archive:
            return [(name, info_size(archive, name), archive.read(name)) for name in archive.namelist() if name.lower().endswith(tuple(SUFFIXES)) and info_size(archive, name) > cfg.binary_limit_mb * 1024 * 1024]
    result = []
    for path in cfg.root.rglob("*"):
        if path.is_file() and path.suffix.lower() in SUFFIXES and path.stat().st_size > cfg.binary_limit_mb * 1024 * 1024:
            text = path.as_posix()
            if ".git" not in path.parts and ".venv" not in path.parts and "build/bin" not in text and "build/obj" not in text and "build/publish" not in text:
                result.append((path.name, path.stat().st_size, path.read_bytes()))
    return result


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Require provenance and SBOM records for large release binaries."""
    candidates = _candidates(cfg)
    for name, size, data in candidates:
        artifacts = cfg.path(cfg.binary_artifacts)
        build = artifacts / (Path(name).name + ".build.json")
        sbom = artifacts / (Path(name).name + ".sbom.json")
        if not build.is_file() or not sbom.is_file():
            return False, f"{name} lacks build/SBOM provenance"
        sbom_record = json.loads(sbom.read_text(encoding="utf-8"))
        scope = sbom_record.get("scope")
        if scope is not None and scope not in SUPPORTED_SCOPES:
            return False, f"{name} has unsupported SBOM scope {scope!r}"
        if sbom_record.get("binary_sha256") and sbom_record["binary_sha256"].upper() != hashlib.sha256(data).hexdigest().upper():
            return False, f"{name} SBOM binary hash mismatch"
        if "binary_size" in sbom_record and int(sbom_record["binary_size"]) != size:
            return False, f"{name} SBOM binary size mismatch"
        record = json.loads(build.read_text(encoding="utf-8"))
        if record.get("sha256", "").upper() != hashlib.sha256(data).hexdigest().upper():
            return False, f"{name} provenance hash mismatch"
        if int(record.get("size_bytes", -1)) != size:
            return False, f"{name} provenance size mismatch"
    return True, f"binaries={len(candidates)}"
