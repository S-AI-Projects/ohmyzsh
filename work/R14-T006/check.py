#!/usr/bin/env python3
"""Characterize autopep8 completion specs and status propagation."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
COMPLETION = ROOT / "plugins/autopep8/_autopep8"
TEST = ROOT / "plugins/autopep8/tests/autopep8.test.zsh"
ZSH = shutil.which("zsh")
CASES = {"success": 0, "argument-error": 37}
EXPECTED = {
    "--help": ("show this help message and exit", ":"),
    "-h": ("show this help message and exit", ":"),
    "--version": ("show program's version number and exit", ":"),
    "--verbose": ("print verbose messages; multiple -v result in more verbose messages", ""),
    "-v": ("print verbose messages; multiple -v result in more verbose messages", ""),
    "--diff": ("print the diff for the fixed source", ""),
    "-d": ("print the diff for the fixed source", ""),
    "--in-place": ("make changes to files in place", ""),
    "-i": ("make changes to files in place", ""),
    "--recursive": ("run recursively; must be used with --in-place or --diff", ""),
    "-r": ("run recursively; must be used with --in-place or --diff", ""),
    "--jobs": ("number of parallel jobs; match CPU count if value is less than 1", "::n        number of parallel jobs; match CPU count if value is:_files"),
    "-j": ("number of parallel jobs; match CPU count if value is less than 1", "::n        number of parallel jobs; match CPU count if value is:_files"),
    "--pep8-passes": ("maximum number of additional pep8 passes (default: 100)", "::n:_files"),
    "-p": ("maximum number of additional pep8 passes (default: 100)", "::n:_files"),
    "-a": ("-a result in more aggressive changes", "::result:_files"),
    "--exclude": ("exclude files/directories that match these comma- separated globs", "::globs:_files"),
    "--list-fixes": ("list codes for fixes; used by --ignore and --select", ""),
    "--ignore": ("do not fix these errors/warnings (default E226,E24)", "::errors:_files"),
    "--select": ("fix only these errors/warnings (e.g. E4,W)", "::errors:_files"),
    "--max-line-length": ("set maximum allowed line length (default: 79)", "::n:_files"),
    "*": (None, "::args:_files"),
}


def run(args: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          check=False)


def read_arguments(path: Path) -> list[str]:
    lines = path.read_text().splitlines()
    if not lines or not lines[0].startswith("COUNT:"):
        raise AssertionError(f"missing _arguments call log: {lines!r}")
    count = int(lines[0].split(":", 1)[1])
    arguments = [shlex.split(line)[0] for line in lines[1:]]
    if count != len(arguments):
        raise AssertionError(f"logged {len(arguments)} args but expected {count}")
    return arguments


def normalize_specs(arguments: list[str]) -> dict[str, tuple[str | None, str]]:
    if arguments[:2] != ["-s", "-S"]:
        raise AssertionError(f"unexpected _arguments control options: {arguments[:2]!r}")
    normalized: dict[str, tuple[str | None, str]] = {}
    for raw in arguments[2:]:
        spec = raw.split(")", 1)[1] if raw.startswith("(") else raw
        match = re.fullmatch(r"(?P<option>--[\w-]+|-[A-Za-z]|\*)(?:\[(?P<description>[^]]*)\])?(?P<tail>.*)", spec)
        if not match:
            raise AssertionError(f"could not parse completion spec: {raw!r}")
        option = match.group("option")
        if option in normalized:
            raise AssertionError(f"duplicate completion for {option}")
        normalized[option] = (match.group("description"), match.group("tail"))
    return normalized


def main() -> int:
    repository_before = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    version = run([ZSH or "zsh", "--version"]).stdout.strip()
    syntax = run([ZSH or "zsh", "-n", str(COMPLETION)])
    actual_cases: list[dict[str, object]] = []
    errors: list[str] = []

    for case, expected_status in CASES.items():
        with tempfile.TemporaryDirectory(prefix=f"autopep8-{case}-") as temp_root:
            temp = Path(temp_root)
            home = temp / "home"
            zdotdir = temp / "zdotdir"
            work_dir = temp / "working directory with spaces"
            stub_bin = temp / "bin"
            for directory in (home, zdotdir, work_dir, stub_bin):
                directory.mkdir()
            (work_dir / "unrelated.txt").write_text("unchanged\n")
            log_path = temp / "arguments.log"
            env = os.environ.copy()
            env.update({
                "HOME": str(home),
                "ZDOTDIR": str(zdotdir),
                "ZSH": str(ROOT),
                "PATH": str(stub_bin),
                "AUTOPEP8_TEST_ROOT": str(temp),
                "AUTOPEP8_ARGUMENTS_STATUS": str(expected_status),
            })
            result = run([ZSH or "zsh", "-f", str(TEST), case, str(ROOT), str(work_dir)], env=env)
            actual_args: list[str] = []
            normalized: dict[str, tuple[str | None, str]] = {}
            log_error = None
            try:
                actual_args = read_arguments(log_path)
                normalized = normalize_specs(actual_args)
            except (AssertionError, OSError, ValueError, IndexError) as exc:
                log_error = str(exc)
            argument_count = len(actual_args)
        valid = result.returncode == 0 and log_error is None and normalized == EXPECTED
        if not valid:
            errors.append(f"{case}: expected status {expected_status}, characterized options, and one passing assertion; got exit {result.returncode}; {log_error or ''}")
        actual_cases.append({
            "case": case,
            "expected_completion_status": expected_status,
            "process_exit_status": result.returncode,
            "passed_named_assertion": result.returncode == 0,
            "arguments_received_by__arguments": actual_args,
            "argument_count": argument_count,
            "normalized_options": {key: list(value) for key, value in normalized.items()},
            "output": result.stdout,
            "log_error": log_error,
        })

    repository_after = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    if syntax.returncode != 0:
        errors.append("zsh syntax check failed")
    if repository_before != repository_after:
        errors.append("repository state changed during the isolated checks")
    if not actual_cases or len(actual_cases) != len(CASES):
        errors.append("zero-case or incomplete run rejected")

    inputs = {
        "completion_file": str(COMPLETION.relative_to(ROOT)),
        "fixture": str(TEST.relative_to(ROOT)),
        "runner": "python3 work/R14-T006/check.py",
        "bootstrap": "zsh -f with temporary HOME, ZDOTDIR, PATH and working directory",
        "_arguments": "stub captures actual completion specifications as separate arguments",
        "external_autopep8": "not invoked; this completion only defines specs",
    }
    expected = {
        "syntax_exit_status": 0,
        "cases": {"success": 0, "argument-error": 37},
        "characterized_options": {key: list(value) for key, value in EXPECTED.items()},
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
        "tool_versions": {"zsh": version, "python": sys.version.split()[0]},
        "errors": errors,
    }
    (EVIDENCE / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    (EVIDENCE / "expected.json").write_text(json.dumps(expected, indent=2) + "\n")
    (EVIDENCE / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    (EVIDENCE / "tool-versions.txt").write_text(f"{version}\nPython {sys.version.split()[0]}\n")

    for case in actual_cases:
        print(case["output"], end="")
    print(f"Native completion syntax check: exit {syntax.returncode}")
    print(f"Repository status entries before/after: {len(repository_before)} / {len(repository_after)}")
    print(f"Evidence saved under {EVIDENCE}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
