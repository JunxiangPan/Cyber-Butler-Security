"""Configuration for the standalone CBP gates."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class GateConfig:
    """Inputs and thresholds for one CBP audit run."""
    root: Path
    coverage_json: Path
    coverage_allowlist: Path
    broker_files: tuple[str, ...] = ("src/broker.py",)
    policy_file: str = "src/broker.py"
    coverage_threshold: float = 80.0
    policy_threshold: float = 85.0
    dependency_lock: Path = Path("requirements.lock")
    installer_core: Path = Path("installer/lib/Installer.Core.ps1")
    docs_manifest: Path = Path("docs/history-manifest.json")
    comment_files: tuple[str, ...] = ("src/broker.py",)
    binary_limit_mb: float = 5.0
    binary_artifacts: Path = Path("artifacts")
    package_zip: Path | None = None
    enable_coverage: bool = True
    enable_dependency: bool = True
    enable_comments: bool = True
    enable_docs: bool = True
    enable_binary: bool = True
    enable_claims: bool = False
    claims_manifest: Path | None = None
    claims_notes: Path | None = None

    def path(self, value: Path | str) -> Path:
        """Resolve a configured path against the repository root."""
        p = Path(value)
        return p if p.is_absolute() else self.root / p


def _read_config(path: Path) -> dict[str, Any]:
    suffix = path.suffix.lower()
    text = path.read_text(encoding="utf-8")
    if suffix == ".json":
        return json.loads(text)
    try:
        import tomllib  # Python 3.11+
    except ModuleNotFoundError:
        try:
            import tomli  # optional fallback
        except ModuleNotFoundError:
            return {}
        return tomli.loads(text)
    return tomllib.loads(text)


def load_config(root: Path, config_path: Path | None, overrides: dict[str, Any] | None = None) -> GateConfig:
    """Load JSON or TOML config and apply command-line overrides."""
    root = root.resolve()
    data: dict[str, Any] = {}
    if config_path and config_path.is_file():
        data = _read_config(config_path)
    data.update(overrides or {})
    cfg = GateConfig(root=root, coverage_json=root / "coverage.json", coverage_allowlist=root / "coverage_allowlist.json")
    for key, value in data.items():
        if not hasattr(cfg, key):
            continue
        if key in {"coverage_json", "coverage_allowlist", "dependency_lock", "installer_core", "docs_manifest", "binary_artifacts", "package_zip", "claims_manifest", "claims_notes"} and value is not None:
            value = Path(value)
        setattr(cfg, key, value)
    return cfg
