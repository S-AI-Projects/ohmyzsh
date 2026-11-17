#!/usr/bin/env python3
"""Run isolated behavioral checks for the zoxide plugin usage example."""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
EVIDENCE = pathlib.Path(__file__).resolve().parent
FIXTURE = ROOT / "plugins/zoxide/tests/zoxide.test.zsh"
PLUGIN = ROOT / "plugins/zoxide/zoxide.plugin.zsh"


def run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, check=False, **kwargs)


def git_state() -> list[str]:
    result = run(["git", "status", "--short"], cwd=ROOT)
    if result.returncode:
        raise AssertionError(f"git status failed: {result.stderr}")
    return result.stdout.splitlines()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    zsh = shutil.which("zsh")
    require(zsh is not None, "zsh is required")
    require(FIXTURE.is_file() and PLUGIN.is_file(), "fixture/plugin missing")
    syntax = run([zsh, "-n", str(PLUGIN)], cwd=ROOT)
    require(syntax.returncode == 0, f"plugin syntax check failed: {syntax.stderr}")

    expected_cases = ["success", "missing-command"]
    cases: list[dict[str, object]] = []
    for case_name in expected_cases:
        with tempfile.TemporaryDirectory(prefix=f"zoxide-{case_name}-") as temporary:
            base = pathlib.Path(temporary)
            home = base / "home"
            zdotdir = base / "zdotdir"
            workdir = base / "working directory with spaces"
            bin_dir = base / "bin"
            target = base / "my project"
            for directory in (home, zdotdir, workdir, bin_dir, target):
                directory.mkdir(parents=True, exist_ok=True)
            argv_log = base / "argv.jsonl"
            output_file = base / "z-output.txt"

            if case_name == "success":
                stub = bin_dir / "zoxide"
                stub.write_text(
                    "#!" + sys.executable + "\n"
                    "import json, os, pathlib, sys\n"
                    "log = pathlib.Path(os.environ['ZOXIDE_ARGV_LOG'])\n"
                    "with log.open('a') as stream: stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                    "args = sys.argv[1:]\n"
                    "if args == ['init', '--cmd', 'z', 'zsh']:\n"
                    "    print('function z { [[ \"$1\" == \"my project\" ]] || return 3; cd -- \"$ZOXIDE_TEST_TARGET\"; print -r -- \"$PWD\"; }')\n"
                    "elif args != ['add', os.environ['ZOXIDE_TEST_TARGET']]:\n"
                    "    sys.exit(64)\n",
                    encoding="utf-8",
                )
                stub.chmod(0o755)

            env = {
                "HOME": str(home),
                "ZDOTDIR": str(zdotdir),
                "ZSH": str(ROOT),
                "PATH": str(bin_dir),
                "ZOXIDE_TEST_TARGET": str(target),
                "ZOXIDE_TEST_OUTPUT": str(output_file),
                "ZOXIDE_ARGV_LOG": str(argv_log),
                "ZTODOXIDE_CASE": case_name,
            }
            before_repository = git_state()
            actual = run([zsh, "-f", str(FIXTURE)], cwd=workdir, env=env)
            after_repository = git_state()
            argv = [json.loads(line) for line in argv_log.read_text().splitlines()] if argv_log.exists() else []
            stdout = actual.stdout
            stderr = actual.stderr
            fields = dict(line.split("=", 1) for line in stdout.splitlines() if "=" in line)

            if case_name == "success":
                expected_argv = [["add", str(target)], ["init", "--cmd", "z", "zsh"]]
                require(actual.returncode == 0, f"success fixture exited {actual.returncode}: {stderr}")
                require(argv == expected_argv, f"zoxide argv mismatch: {argv!r}")
                require(f"command_output={target}" in stdout, f"documented output missing: {stdout!r}")
                require("before_pwd" in fields and fields["before_pwd"] != str(target), f"before state missing: {stdout!r}")
                require(fields.get("after_pwd") == str(target), f"after state missing: {stdout!r}")
                require("command_status=0" in stdout, f"success status missing: {stdout!r}")
                require("setup_status=0" in stdout and "bootstrap_status=0" in stdout, stdout)
            else:
                warning = "zoxide not found, please install it"
                require(actual.returncode == 0, f"missing-command fixture exited {actual.returncode}: {stderr}")
                require(argv == [], f"zoxide unexpectedly ran: {argv!r}")
                require(warning in stdout, f"plugin warning missing: {stdout!r}")
                require("function_z=0" in stdout, f"z function should not exist: {stdout!r}")
                require("before_pwd" in fields and fields.get("after_pwd") == fields["before_pwd"], f"PWD changed: {stdout!r}")

            require(before_repository == after_repository, "repository state changed during isolated fixture")
            cases.append(
                {
                    "name": case_name,
                    "input": {"cwd": str(workdir), "target": str(target), "path": str(bin_dir)},
                    "expected": {
                        "exit_status": 0,
                        "argv": [["add", str(target)], ["init", "--cmd", "z", "zsh"]]
                        if case_name == "success"
                        else [],
                        "state": "PWD changes to target" if case_name == "success" else "PWD unchanged; z function absent",
                    },
                    "actual": {
                        "exit_status": actual.returncode,
                        "argv": argv,
                        "stdout": stdout,
                        "stderr": stderr,
                        "state_before": fields.get("before_pwd"),
                        "state_after": fields.get("after_pwd"),
                        "repository_before": before_repository,
                        "repository_after": after_repository,
                    },
                }
            )
            print(f"PASS: {case_name} | shell_exit_status={actual.returncode} | argv={argv!r}")
            print(f"  stdout={stdout.rstrip()!r}")
            print(f"  stderr={stderr.rstrip()!r}")
            print(f"  repository_before={before_repository!r} repository_after={after_repository!r}")

    require(cases, "zero-case run is not accepted")
    require([case["name"] for case in cases] == expected_cases, f"wrong test cases: {cases!r}")
    versions = {
        "python": sys.version.splitlines()[0],
        "zsh": run([zsh, "--version"]).stdout.strip(),
        "git": run(["git", "--version"]).stdout.strip(),
    }
    evidence = {
        "test_names": expected_cases,
        "syntax_check": {"command": f"zsh -n {PLUGIN.relative_to(ROOT)}", "exit_status": syntax.returncode},
        "cases": cases,
        "tool_versions": versions,
    }
    (EVIDENCE / "inputs.json").write_text(json.dumps({"cases": expected_cases}, indent=2) + "\n")
    (EVIDENCE / "expected.json").write_text(json.dumps({"cases": [case["expected"] for case in cases]}, indent=2) + "\n")
    (EVIDENCE / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    (EVIDENCE / "tool-versions.txt").write_text("\n".join(f"{key}: {value}" for key, value in versions.items()) + "\n")
    print(f"Native syntax check: exit {syntax.returncode}; cases executed: {len(cases)}")
    print(f"Evidence saved under {EVIDENCE}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
