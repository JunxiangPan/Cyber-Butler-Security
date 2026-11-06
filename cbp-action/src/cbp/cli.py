"""Standalone CBP CLI."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import binary_gate, claims_gate, comment_gate, coverage_gate, dependency_gate, docs_gate
from .config import load_config


def main(argv: list[str] | None = None) -> int:
    """Run enabled CBP gates and return a process exit code."""
    parser = argparse.ArgumentParser(prog="cbp")
    parser.add_argument("--root", default=".")
    parser.add_argument("--config", default="")
    parser.add_argument("--mode", choices=("audit", "enforce"), default="enforce")
    parser.add_argument("--coverage-threshold", type=float, default=None)
    parser.add_argument("--policy-coverage-threshold", type=float, default=None)
    args = parser.parse_args(argv)
    config_path = Path(args.config) if args.config else Path(args.root) / "cbp.json"
    overrides = {}
    if args.coverage_threshold is not None:
        overrides["coverage_threshold"] = args.coverage_threshold
    if args.policy_coverage_threshold is not None:
        overrides["policy_threshold"] = args.policy_coverage_threshold
    cfg = load_config(Path(args.root), config_path, overrides)
    checks = []
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
    return 0 if ok or args.mode == "audit" else 1


if __name__ == "__main__":
    raise SystemExit(main())
