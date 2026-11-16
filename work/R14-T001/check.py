#!/usr/bin/env python3
"""Run the Rails plugin's isolated zsh checks and save reproducible evidence."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import os
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
TEST = ROOT / "plugins/rails/tests/rails.test.zsh"
PLUGIN = ROOT / "plugins/rails/rails.plugin.zsh"


def run(args: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, check=False)


def main() -> int:
    before = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    version = run(["zsh", "--version"])
    py_version = sys.version.split()[0]
    syntax = run(["zsh", "-n", str(PLUGIN)])
    isolated_zdotdir = tempfile.TemporaryDirectory(prefix="rails-zdotdir-")
    test_env = os.environ.copy()
    test_env["ZDOTDIR"] = isolated_zdotdir.name
    test_env["ZSH"] = str(ROOT)
    test = run(["zsh", "-f", str(TEST), str(ROOT)], env=test_env)
    isolated_zdotdir.cleanup()
    observed_cases = [line.split("PASS: ", 1)[1].split(" | output=", 1)[0]
                      for line in test.stdout.splitlines()
                      if line.startswith("PASS: ") and " | output=" in line]
    summary = next((line for line in test.stdout.splitlines() if line.endswith("failures")), "")
    errors: list[str] = []
    if syntax.returncode != 0:
        errors.append("zsh syntax check failed")
    if test.returncode != 0:
        errors.append("Rails zsh test suite failed")
    if len(observed_cases) < 2:
        errors.append("zero-case runs are rejected")
    if not any("ordinary success" in name for name in observed_cases):
        errors.append("an ordinary-success assertion did not execute")
    if not any(any(marker in name for marker in ("edge", "missing", "failure"))
               for name in observed_cases):
        errors.append("a documented failure/edge-state assertion did not execute")
    if summary:
        pieces = summary.split()
        if not pieces or not pieces[0].isdigit() or int(pieces[0]) != len(observed_cases):
            errors.append("reported case count does not match observed named cases")
        if "0 failures" not in summary:
            errors.append("the zsh suite reported assertion failures")
    else:
        errors.append("the zsh suite did not report a test count")
    after = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    if before != after:
        errors.append("repository status changed while checks were running")

    evidence = {
        "inputs": {
            "plugin": str(PLUGIN.relative_to(ROOT)),
            "test": str(TEST.relative_to(ROOT)),
            "runner": "python3 work/R14-T001/check.py",
            "fixture": "zsh -f launched with temporary ZDOTDIR; temporary project; stubbed PATH commands rails/rake/tail/ruby/bundle",
        },
        "expected": {
            "syntax_exit_status": 0,
            "required_case_types": ["ordinary success", "documented failure or edge state"],
            "minimum_case_count": 2,
            "repository_status_before_equals_after": True,
        },
        "actual": {
            "syntax_exit_status": syntax.returncode,
            "syntax_output": syntax.stdout,
            "test_exit_status": test.returncode,
            "test_output": test.stdout,
            "observed_test_names": observed_cases,
            "test_summary": summary,
            "repository_status_before": before,
            "repository_status_after": after,
        },
        "tool_versions": {"zsh": version.stdout.strip(), "python": py_version},
        "errors": errors,
    }
    (EVIDENCE / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    expected = {"required_case_types": ["ordinary success", "documented failure or edge state"],
                "minimum_case_count": 2, "expected_syntax_exit_status": 0,
                "zero_cases_rejected": True}
    (EVIDENCE / "expected.json").write_text(json.dumps(expected, indent=2) + "\n")
    (EVIDENCE / "inputs.json").write_text(json.dumps(evidence["inputs"], indent=2) + "\n")
    (EVIDENCE / "tool-versions.txt").write_text(
        f"{version.stdout.strip()}\nPython {py_version}\n")
    print(test.stdout, end="")
    print(f"Native syntax check: exit {syntax.returncode}")
    print(f"Repository status before/after check: {len(before)} / {len(after)} entries")
    print(f"Evidence: {EVIDENCE}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
