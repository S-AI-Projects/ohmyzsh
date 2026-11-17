#!/usr/bin/env python3
"""Run isolated Ant plugin state-transition checks and save evidence."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
PLUGIN = ROOT / "plugins/ant/ant.plugin.zsh"
TEST = ROOT / "plugins/ant/tests/ant.test.zsh"
CASES = {
    "default": "Ant plugin supplies the default colored logger",
    "preserve-custom": "Ant plugin preserves a custom ANT_ARGS value",
}


def run(args: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          check=False)


def main() -> int:
    status_before = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    zsh_version = run(["zsh", "--version"])
    syntax = run(["zsh", "-n", str(PLUGIN)])
    actual_cases: list[dict[str, object]] = []
    errors: list[str] = []

    for case, expected_name in CASES.items():
        with tempfile.TemporaryDirectory(prefix=f"ant-{case}-") as temp_root:
            env = os.environ.copy()
            env["ZDOTDIR"] = str(Path(temp_root) / "zdotdir")
            env["ANT_TEST_ROOT"] = temp_root
            env["ANT_TEST_UNRELATED"] = "keep-this-value"
            if case == "preserve-custom":
                env["ANT_ARGS"] = "-verbose -Dmessage=two words"
            else:
                env.pop("ANT_ARGS", None)
            result = run(["zsh", "-f", str(TEST), case, str(ROOT)], env=env)
        pass_lines = [line for line in result.stdout.splitlines()
                      if line.startswith(f"PASS: {case} |")]
        valid = result.returncode == 0 and len(pass_lines) == 1
        if not valid:
            errors.append(f"{case}: expected one passing named assertion, got exit {result.returncode}")
        actual_cases.append({
            "case": case,
            "expected_assertion": expected_name,
            "exit_status": result.returncode,
            "passed_named_assertion": len(pass_lines) == 1,
            "output": result.stdout,
        })

    status_after = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    if syntax.returncode != 0:
        errors.append("zsh syntax check failed")
    if status_before != status_after:
        errors.append("repository status changed while the isolated checks ran")
    if not actual_cases or len(actual_cases) != len(CASES):
        errors.append("zero-case or incomplete run rejected")

    inputs = {
        "plugin": str(PLUGIN.relative_to(ROOT)),
        "shell_test": str(TEST.relative_to(ROOT)),
        "runner": "python3 work/R14-T003/check.py",
        "invocation": "zsh -f with temporary ZDOTDIR and ANT_TEST_ROOT",
        "external_commands": "none; plugin initialization only sets ANT_ARGS",
        "unrelated_state": "ANT_TEST_UNRELATED=keep-this-value",
    }
    expected = {
        "syntax_exit_status": 0,
        "assertions": list(CASES.values()),
        "case_count": len(CASES),
        "custom_ANT_ARGS_preserved": True,
        "unrelated_shell_state_unchanged": True,
        "repository_status_before_equals_after": True,
    }
    results = {
        "inputs": inputs,
        "expected": expected,
        "actual": {
            "syntax_exit_status": syntax.returncode,
            "syntax_output": syntax.stdout,
            "cases": actual_cases,
            "repository_status_before": status_before,
            "repository_status_after": status_after,
        },
        "tool_versions": {
            "zsh": zsh_version.stdout.strip(),
            "python": sys.version.split()[0],
        },
        "errors": errors,
    }
    (EVIDENCE / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    (EVIDENCE / "expected.json").write_text(json.dumps(expected, indent=2) + "\n")
    (EVIDENCE / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    (EVIDENCE / "tool-versions.txt").write_text(
        f"{zsh_version.stdout.strip()}\nPython {sys.version.split()[0]}\n")

    for case in actual_cases:
        print(case["output"], end="")
    print(f"Native syntax check: exit {syntax.returncode}")
    print(f"Repository status entries before/after: {len(status_before)} / {len(status_after)}")
    print(f"Evidence saved under {EVIDENCE}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
