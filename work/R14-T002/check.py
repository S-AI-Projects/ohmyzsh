#!/usr/bin/env python3
"""Run isolated NVM plugin initialization tests and save their evidence."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
PLUGIN = ROOT / "plugins/nvm/nvm.plugin.zsh"
TEST = ROOT / "plugins/nvm/tests/nvm.test.zsh"
EXPECTED_CASES = {
    "minimum": "nvm minimum lazy trigger",
    "optional": "nvm optional lazy command argument",
    "invalid-combination": "documented invalid combination (lazy-cmd without lazy)",
}


def run(args: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, check=False)


def main() -> int:
    before = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    zsh_version = run(["zsh", "--version"])
    python_version = sys.version.split()[0]
    syntax = run(["zsh", "-n", str(PLUGIN)])
    actual_cases: list[dict[str, object]] = []
    errors: list[str] = []

    for case, expected_name in EXPECTED_CASES.items():
        with tempfile.TemporaryDirectory(prefix=f"nvm-{case}-zdotdir-") as zdotdir, \
                tempfile.TemporaryDirectory(prefix=f"nvm-{case}-state-") as state_dir:
            env = os.environ.copy()
            env["ZDOTDIR"] = zdotdir
            env["NVM_TEST_ROOT"] = state_dir
            result = run(["zsh", "-f", str(TEST), case, str(ROOT)], env=env)
        pass_lines = [line for line in result.stdout.splitlines()
                      if line.startswith(f"PASS: {expected_name} |")]
        valid = result.returncode == 0 and len(pass_lines) == 1
        if not valid:
            errors.append(f"{case}: expected exactly one passing named assertion; got exit {result.returncode}")
        actual_cases.append({
            "case": case,
            "expected_test_name": expected_name,
            "exit_status": result.returncode,
            "passed_named_assertion": len(pass_lines) == 1,
            "output": result.stdout,
        })

    after = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    if syntax.returncode != 0:
        errors.append("zsh syntax check failed")
    if before != after:
        errors.append("repository status changed while the tests ran")
    if len(actual_cases) != len(EXPECTED_CASES):
        errors.append("zero-case or incomplete run rejected")

    inputs = {
        "plugin": str(PLUGIN.relative_to(ROOT)),
        "shell_test": str(TEST.relative_to(ROOT)),
        "runner": "python3 work/R14-T002/check.py",
        "isolation": "zsh -f with per-case temporary ZDOTDIR and NVM_TEST_ROOT",
        "stubs": "temporary nvm.sh, bash_completion, and custom_tool command",
    }
    evidence = {
        "inputs": inputs,
        "expected": {
            "syntax_exit_status": 0,
            "case_names": list(EXPECTED_CASES.values()),
            "case_count": len(EXPECTED_CASES),
            "repository_status_before_equals_after": True,
        },
        "actual": {
            "syntax_exit_status": syntax.returncode,
            "syntax_output": syntax.stdout,
            "cases": actual_cases,
            "repository_status_before": before,
            "repository_status_after": after,
        },
        "tool_versions": {"zsh": zsh_version.stdout.strip(), "python": python_version},
        "errors": errors,
    }
    (EVIDENCE / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    (EVIDENCE / "expected.json").write_text(json.dumps(evidence["expected"], indent=2) + "\n")
    (EVIDENCE / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    (EVIDENCE / "tool-versions.txt").write_text(
        f"{zsh_version.stdout.strip()}\nPython {python_version}\n")

    for case in actual_cases:
        print(case["output"], end="")
    print(f"Native syntax check: exit {syntax.returncode}")
    print(f"Repository status before/after: {len(before)} / {len(after)} entries")
    print(f"Evidence saved under {EVIDENCE}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
