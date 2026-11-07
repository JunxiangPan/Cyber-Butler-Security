"""Standalone CBP CLI."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from . import baseline, binary_gate, suppression, claims_gate, comment_gate, coverage_gate, custom_rules, dependency_gate, docs_gate, encoding_gate, sarif, upgrade_gate, verify_release
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
    parser.add_argument("--coverage-signature", default="")
    parser.add_argument("--require-coverage-signature", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--dependency-lock", default="")
    parser.add_argument("--install-command", default="")
    parser.add_argument("--installer-core", dest="install_command", default=argparse.SUPPRESS)
    parser.add_argument("--docs-manifest", default="")
    parser.add_argument("--binary-artifacts", default="")
    parser.add_argument("--package-zip", default="")
    parser.add_argument("--claims-manifest", default="")
    parser.add_argument("--claims-notes", default="")
    parser.add_argument("--release-body", default="")
    parser.add_argument("--manifest", default="")
    parser.add_argument("--sarif-output", default="")
    parser.add_argument("--baseline", default="")
    parser.add_argument("--generate-baseline", default="")
    parser.add_argument("--verify-release", default="")
    parser.add_argument("--repository", default="")
    parser.add_argument("--enable-coverage", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-encoding", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-dependency", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-comments", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-docs", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-binary", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-claims", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-custom", type=lambda x: x.lower() == "true", default=None)
    parser.add_argument("--enable-upgrade", type=lambda x: x.lower() == "true", default=None)
    args = parser.parse_args(argv)
    if args.verify_release:
        repository = args.repository or os.environ.get("GITHUB_REPOSITORY", "")
        if not repository:
            print("VERIFY_RELEASE_FAILED: --repository or GITHUB_REPOSITORY is required")
            return 1
        body = Path(args.release_body) if args.release_body else Path(args.root) / "docs" / "RELEASE_BODY.md"
        ok, detail = verify_release.verify(repository, args.verify_release, body, verify_release.token_from_env())
        print(("RELEASE_BODY_OK " if ok else "") + detail)
        return 0 if ok else 1
    config_path = Path(args.config) if args.config else Path(args.root) / "cbp.json"
    if not args.config and not config_path.is_file():
        config_path = Path(args.root) / ".cbp" / "config.json"
    overrides = {}
    if args.coverage_threshold is not None:
        overrides["coverage_threshold"] = args.coverage_threshold
    if args.policy_coverage_threshold is not None:
        overrides["policy_threshold"] = args.policy_coverage_threshold
    for key, value in {
        "coverage_json": args.coverage_json, "coverage_allowlist": args.coverage_allowlist, "coverage_signature": args.coverage_signature,
        "dependency_lock": args.dependency_lock, "install_command": args.install_command,
        "docs_manifest": args.docs_manifest, "binary_artifacts": args.binary_artifacts,
        "package_zip": args.package_zip, "claims_manifest": args.claims_manifest,
        "claims_notes": args.claims_notes, "release_body": args.release_body, "baseline": args.baseline,
    }.items():
        if value:
            overrides[key] = value
    if args.manifest:
        overrides["claims_manifest"] = args.manifest
    for key in ("enable_coverage", "require_coverage_signature", "enable_encoding", "enable_dependency", "enable_comments", "enable_docs", "enable_binary", "enable_claims", "enable_custom", "enable_upgrade"):
        value = getattr(args, key)
        if value is not None:
            overrides[key] = value
    cfg = load_config(Path(args.root), config_path, overrides)
    checks = []
    if cfg.enable_encoding:
        checks.append(("encoding", encoding_gate.run))
    if cfg.enable_coverage:
        checks.append(("coverage", coverage_gate.run))
    if cfg.enable_dependency:
        checks.append(("dependency", dependency_gate.run))
    if cfg.enable_comments:
        checks.append(("comments", comment_gate.run))
    if cfg.enable_docs:
        checks.append(("docs", docs_gate.run))
    if cfg.enable_claims:
        checks.append(("claims", claims_gate.run))
    if cfg.enable_custom:
        checks.append(("custom", custom_rules.run))
    if cfg.enable_upgrade:
        checks.append(("upgrade", upgrade_gate.run))
    if cfg.enable_binary:
        checks.append(("binary", binary_gate.run))
    ok = True
    gate_results = []
    for name, check in checks:
        passed, detail = check(cfg)
        filtered = suppression.filter_text(cfg.root, detail)
        if filtered != detail:
            passed = passed or not filtered.strip()
            detail = filtered or "inline-suppressed"
        gate_results.append((name, passed, detail))
        print(f"{name}: {'PASS' if passed else 'FAIL'} {detail}")
        ok = ok and passed
    if not checks:
        ok = False
    baseline_path = Path(args.generate_baseline) if args.generate_baseline else Path(args.baseline) if args.baseline else Path(args.root) / "cbp-baseline.json"
    if args.generate_baseline:
        entries = []
        for gate, passed, detail in gate_results:
            if not passed:
                entries.extend((gate, line) for line in detail.splitlines() if line.strip())
        baseline.write_entries(baseline_path, entries)
        print(f"BASELINE_WRITTEN path={baseline_path} entries={len(entries)}")
        return 0
    allowed_baseline = baseline.load(baseline_path)
    if allowed_baseline:
        adjusted = []
        for gate, passed, detail in gate_results:
            kept = [line for line in detail.splitlines() if baseline.fingerprint(gate, line) not in allowed_baseline]
            if not passed and not any(line.strip() for line in kept):
                passed = True
            adjusted.append((gate, passed, chr(10).join(kept) if kept else "baseline-suppressed"))
        gate_results = adjusted
        ok = all(passed for _, passed, _ in gate_results)
    if args.sarif_output:
        try:
            target = Path(args.sarif_output)
            document = sarif.build(gate_results, Path(args.root))
            target.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        except OSError as exc:
            print(f"sarif: FAIL cannot write {args.sarif_output}: {exc}")
            ok = False
    print("CBP_RESULT=" + ("PASS" if ok else "FAIL") + " gates_ran=" + str(len(checks)))
    return 0 if ok or args.mode in {"audit", "warn"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
