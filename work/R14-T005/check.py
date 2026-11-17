#!/usr/bin/env python3
"""Run deterministic asdf plugin initialization checks and save evidence."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
PLUGIN = ROOT / "plugins/asdf/asdf.plugin.zsh"
TEST = ROOT / "plugins/asdf/tests/asdf.test.zsh"
ZSH = shutil.which("zsh")
CASES = {
    "success": "asdf is available: local default, shim path, completion and argv are correct",
    "missing-dependency": "asdf is unavailable: plugin returns without changing shell state",
}


def run(args: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          check=False)


def tree_state(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): path.read_text()
        for path in sorted(root.rglob("*")) if path.is_file()
    }


def main() -> int:
    repository_before = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    zsh_version = run([ZSH or "zsh", "--version"])
    syntax = run([ZSH or "zsh", "-n", str(PLUGIN)])
    actual_cases: list[dict[str, object]] = []
    errors: list[str] = []

    for case, assertion in CASES.items():
        with tempfile.TemporaryDirectory(prefix=f"asdf-{case}-") as temp_root:
            temp = Path(temp_root)
            home = temp / "temporary home"
            work_dir = temp / "working directory with spaces"
            cache = temp / "cache"
            zdotdir = temp / "zdotdir"
            stub_dir = temp / "bin"
            for directory in (home, work_dir, cache / "completions", zdotdir, stub_dir):
                directory.mkdir(parents=True, exist_ok=True)
            (work_dir / "unrelated.txt").write_text("must remain unchanged\n")
            stub_log = temp / "asdf-argv.log"
            if case == "success":
                stub = stub_dir / "asdf"
                stub.write_text(
                    "#!/bin/zsh\n"
                    "print -r -- \"COUNT:$#\" >| \"$ASDF_TEST_LOG\"\n"
                    "for arg in \"$@\"; do print -r -- \"${(qqq)arg}\" >> \"$ASDF_TEST_LOG\"; done\n"
                    "print -r -- '#compdef asdf'\n"
                    "print -r -- 'EXIT:0' >> \"$ASDF_TEST_LOG\"\n"
                    "exit 0\n"
                )
                stub.chmod(0o755)
            before_work = tree_state(work_dir)
            expected_path = str(stub_dir)
            env = os.environ.copy()
            env.update({
                "HOME": str(home),
                "ZDOTDIR": str(zdotdir),
                "ZSH": str(ROOT),
                "ZSH_CACHE_DIR": str(cache),
                "PATH": expected_path,
                "ASDF_TEST_ROOT": str(temp),
                "ASDF_TEST_LOG": str(stub_log),
                "ASDF_TEST_INITIAL_PATH": expected_path,
            })
            env.pop("ASDF_DATA_DIR", None)
            result = run([ZSH or "zsh", "-f", str(TEST), case, str(ROOT), str(work_dir)], env=env)
            after_work = tree_state(work_dir)
            completion_path = cache / "completions" / "_asdf"
            completion = completion_path.read_text() if completion_path.exists() else None
            actual_argv = stub_log.read_text().splitlines() if stub_log.exists() else []
        pass_lines = [line for line in result.stdout.splitlines()
                      if line.startswith(f"PASS: {case} |")]
        valid = result.returncode == 0 and len(pass_lines) == 1 and before_work == after_work
        if not valid:
            errors.append(f"{case}: expected one passing assertion, unchanged temporary working tree, and exit 0; got exit {result.returncode}")
        actual_cases.append({
            "case": case,
            "expected_assertion": assertion,
            "exit_status": result.returncode,
            "passed_named_assertion": len(pass_lines) == 1,
            "output": result.stdout,
            "asdf_argv_log_lines": actual_argv,
            "asdf_exit_status": actual_argv[-1].removeprefix("EXIT:") if actual_argv and actual_argv[-1].startswith("EXIT:") else None,
            "completion_file_contents": completion,
            "working_tree_before": before_work,
            "working_tree_after": after_work,
            "working_tree_unchanged": before_work == after_work,
        })

    repository_after = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    if syntax.returncode != 0:
        errors.append("zsh syntax check failed")
    if repository_before != repository_after:
        errors.append("repository state changed while checks ran")
    if not actual_cases or len(actual_cases) != len(CASES):
        errors.append("zero-case or incomplete run rejected")

    inputs = {
        "plugin": str(PLUGIN.relative_to(ROOT)),
        "shell_test": str(TEST.relative_to(ROOT)),
        "runner": "python3 work/R14-T005/check.py",
        "bootstrap": "zsh -f, explicit plugin source, temporary ZDOTDIR and HOME",
        "working_directory": "per-case temporary directory with spaces",
        "external_command": "temporary PATH containing only the asdf stub in success case; empty in missing-dependency case",
        "stubbed_arguments": ["completion", "zsh"],
    }
    expected = {
        "syntax_exit_status": 0,
        "assertions": list(CASES.values()),
        "case_count": len(CASES),
        "success_sets_local_data_dir_shims_and_completion": True,
        "missing_dependency_leaves_shell_state_unchanged": True,
        "temporary_working_tree_unchanged": True,
        "repository_status_before_equals_after": True,
    }
    results = {
        "inputs": inputs,
        "expected": expected,
        "actual": {
            "syntax_exit_status": syntax.returncode,
            "syntax_output": syntax.stdout,
            "cases": actual_cases,
            "repository_status_before": repository_before,
            "repository_status_after": repository_after,
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
    print(f"Repository status entries before/after: {len(repository_before)} / {len(repository_after)}")
    print(f"Evidence saved under {EVIDENCE}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
