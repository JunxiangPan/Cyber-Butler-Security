"""Standalone CBP CLI."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import binary_gate, claims_gate, comment_gate, coverage_gate, dependency_gate, docs_gate, encoding_gate
from .config import load_config


def main(argv: list[str] | None = None) -> int:
    """Run enabled CBP gates and return a process exit code."""
    parser = argparse.ArgumentParser(prog="cbp")
    parser.add_argument("--root", default=".")
    parser.add_argument("--config", default="")
    parser.add_argument("--mode", choices=("audit", "warn", "enforce"), default="enforce")
    parser.add_argument("--coverage-threshold", type=float, default=None)
    parser.add_argument("--policy-coverage-threshold", type=float, default=None)
    parser.add_argument("--coverage-json", default="")
    parser.add_argument("--coverage-allowlist", default="")
    parser.add_argument("--dependency-lock", default="")
    parser.add_argument("--install-command", default="")
    parser.add_argument("--docs-manifest", default="")
    parser.add_argument("--binary-artifacts", default="")
    parser.add_argument("--package-zip", default="")
    parser.add_argument("--claims-manifest", default="")
    parser.add_argument("--claims-notes", default="")
    parser.add_argument("--manifest", default="")
    parser.add_argument("--enable-coverage", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-encoding", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-dependency", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-comments", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-docs", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-binary", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-claims", type=lambda x: x.lower() == "true", default=None)
    args = parser.parse_args(argv)
    config_path = Path(args.config) if args.config else Path(args.root) / "cbp.json"
    if not args.config and not config_path.is_file():
        config_path = Path(args.root) / ".cbp" / "config.json"
    overrides = {}
    if args.coverage_threshold is not None:
        overrides["coverage_threshold"] = args.coverage_threshold
    if args.policy_coverage_threshold is not None:
        overrides["policy_threshold"] = args.policy_coverage_threshold
    for key, value in {
        "coverage_json": args.coverage_json, "coverage_allowlist": args.coverage_allowlist,
        "dependency_lock": args.dependency_lock, "install_command": args.install_command,
        "docs_manifest": args.docs_manifest, "binary_artifacts": args.binary_artifacts,
        "package_zip": args.package_zip, "claims_manifest": args.claims_manifest,
        "claims_notes": args.claims_notes,
    }.items():
        if value:
            overrides[key] = value
    if args.manifest:
        overrides["claims_manifest"] = args.manifest
    for key in ("enable_coverage", "enable_encoding", "enable_dependency", "enable_comments", "enable_docs", "enable_binary", "enable_claims"):
        value = getattr(args, key)
        if value is not None:
            overrides[key] = value
    cfg = load_config(Path(args.root), config_path, overrides)
    checks = []
    if getattr(cfg, "enable_encoding", True):
        checks.append(("encoding", encoding_gate.run))
    if cfg.enable_coverage:
        checks.append(("coverage", coverage_gate.run))
    if cfg.enable_dependency:
        checks.append(("dependency", dependency_gate.run))
    if cfg.enable_comments:
        checks.append(("comments", comment_gate.run))
    if cfg.enable_docs:
        checks.append(("docs", docs_gate.run))
    if getattr(cfg, "enable_claims", True):
        checks.append(("claims", claims_gate.run))
    if cfg.enable_binary:
        checks.append(("binary", binary_gate.run))
    ok = True
    for name, check in checks:
        passed, detail = check(cfg)
        print(f"{name}: {'PASS' if passed else 'FAIL'} {detail}")
        ok = ok and passed
    print("CBP_RESULT=" + ("PASS" if ok else "FAIL"))
    return 0 if ok or args.mode in {"audit", "warn"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
