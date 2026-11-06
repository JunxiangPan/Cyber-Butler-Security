"""Configuration for the standalone CBP gates."""
from __future__ import annotations

import json
import re
import sys
import warnings
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "0.1.4"
LEGACY_FIELDS = {
    "installer_core": "install_command",
    "broker_files": "target_files",
    "measured_files": "target_files",
}


@dataclass
class GateConfig:
    """Inputs and thresholds for one CBP audit run."""
    root: Path
    schema_version: str = SCHEMA_VERSION
    coverage_json: Path | str = ""
    coverage_allowlist: Path | str = ""
    target_files: tuple[str, ...] = ()
    coverage_groups: tuple[dict[str, Any], ...] = ()
    policy_file: str = ""
    coverage_threshold: float = 80.0
    policy_threshold: float = 85.0
    dependency_lock: Path | str = ""
    install_command: Path | str = ""
    custom_rules: tuple[dict, ...] = ()
    evidence_readers: dict = field(default_factory=dict)
    upgrade_script: str = ""
    upgrade_fixtures: tuple[str, ...] = ()
    previous_schema: str = ""
    current_schema: str = ""
    allow_breaking_changes: bool = False
    upgrade_timeout_seconds: int = 120
    docs_manifest: Path | str = ""
    comment_files: tuple[str, ...] = ()
    binary_limit_mb: float = 5.0
    binary_artifacts: Path | str = ""
    package_zip: Path | None = None
    enable_coverage: bool = True
    enable_encoding: bool = True
    enable_dependency: bool = True
    enable_comments: bool = True
    enable_docs: bool = True
    enable_binary: bool = True
    enable_claims: bool = False
    enable_custom: bool = True
    enable_upgrade: bool = True
    claims_manifest: Path | None = None
    claims_notes: Path | None = None
    release_body: Path | str = ""
    baseline: Path | str = ""
    coverage_signature: Path | str = ""
    require_coverage_signature: bool = False

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
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "TOML configuration requires Python 3.11+ or the tomli package; "
                "install tomli instead of silently using an empty configuration"
            ) from exc
        return tomli.loads(text)
    return tomllib.loads(text)


def _warn(message: str) -> None:
    print("CBP_CONFIG_WARN: " + message, file=sys.stderr)
    warnings.warn(message, DeprecationWarning, stacklevel=3)


def _migrate(data: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    warnings_out: list[str] = []
    declared = data.get("schema_version")
    if declared is None:
        declared = "0.1.0"
        warnings_out.append("schema_version missing; assuming legacy 0.1.0 and auto-migrating in memory")
    if not isinstance(declared, str) or not re.fullmatch(r"\d+\.\d+\.\d+", declared):
        raise ValueError("schema_version must be a semantic version such as 0.1.2")
    current = tuple(int(part) for part in SCHEMA_VERSION.split("."))
    found = tuple(int(part) for part in declared.split("."))
    if found > current:
        raise ValueError(f"unsupported future schema_version {declared}; this CBP supports {SCHEMA_VERSION}")
    migrated = dict(data)
    for old, new in LEGACY_FIELDS.items():
        if old in migrated and new not in migrated:
            migrated[new] = migrated.pop(old)
            warnings_out.append(f"legacy field {old!r} mapped to {new!r}; update cbp.json before v0.2.0")
    if declared != SCHEMA_VERSION:
        warnings_out.append(f"config schema {declared} was migrated to {SCHEMA_VERSION} in memory; update the checked-in file")
    migrated["schema_version"] = SCHEMA_VERSION
    return migrated, warnings_out


def load_config(root: Path, config_path: Path | None, overrides: dict[str, Any] | None = None) -> GateConfig:
    """Load JSON or TOML config and apply command-line overrides."""
    root = root.resolve()
    data: dict[str, Any] = {}
    if config_path and config_path.is_file():
        data = _read_config(config_path)
    data.update(overrides or {})
    data, migration_warnings = _migrate(data)
    unknown = sorted(set(data) - set(GateConfig.__dataclass_fields__))
    if unknown:
        raise ValueError("unknown cbp.json key(s): " + ", ".join(unknown))
    for message in migration_warnings:
        _warn(message)
    cfg = GateConfig(root=root, schema_version=SCHEMA_VERSION)
    for key, value in data.items():
        if not hasattr(cfg, key):
            continue
        if key in {"coverage_json", "coverage_allowlist", "dependency_lock", "install_command", "docs_manifest", "binary_artifacts", "package_zip", "claims_manifest", "claims_notes"} and value is not None:
            value = Path(value)
        setattr(cfg, key, value)
    return cfg
