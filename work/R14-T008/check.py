#!/usr/bin/env python3
"""Run the brew bci failure-and-recovery scenario in isolated Zsh."""

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
PLUGIN = ROOT / "plugins/brew/brew.plugin.zsh"
FIXTURE = ROOT / "plugins/brew/tests/brew.test.zsh"


def run(command: list[str], *, cwd: pathlib.Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True, check=False)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def git_state() -> list[str]:
    result = run(["git", "status", "--short"], cwd=ROOT)
    if result.returncode != 0:
        raise AssertionError(f"git status failed: {result.stderr}")
    return result.stdout.splitlines()


def main() -> int:
    zsh = shutil.which("zsh")
    require(zsh is not None, "zsh is required")
    require(PLUGIN.is_file() and FIXTURE.is_file(), "brew plugin or fixture is missing")
    syntax = run([zsh, "-n", str(PLUGIN)], cwd=ROOT)
    require(syntax.returncode == 0, f"plugin syntax check failed: {syntax.stderr}")

    with tempfile.TemporaryDirectory(prefix="brew-bci-") as temporary:
        base = pathlib.Path(temporary)
        home = base / "home"
        zdotdir = base / "zdotdir"
        working = base / "working directory with spaces"
        bin_dir = base / "bin"
        prefix = base / "homebrew-prefix"
        for directory in (home, zdotdir, working, bin_dir, prefix):
            directory.mkdir(parents=True, exist_ok=True)
        argv_log = base / "argv.jsonl"
        paths = {
            "BREW_TEST_FAILURE_OUT": base / "failure.stdout",
            "BREW_TEST_FAILURE_ERR": base / "failure.stderr",
            "BREW_TEST_SUCCESS_OUT": base / "success.stdout",
            "BREW_TEST_SUCCESS_ERR": base / "success.stderr",
        }
        stub = bin_dir / "brew"
        stub.write_text(
            "#!" + sys.executable + "\n"
            "import json, os, sys\n"
            "args = sys.argv[1:]\n"
            "with open(os.environ['BREW_ARGV_LOG'], 'a') as stream: stream.write(json.dumps(args) + '\\n')\n"
            "if args == ['info', '--cask']:\n"
            "    print('Error: no cask name was provided (use: bci <cask>)', file=sys.stderr)\n"
            "    sys.exit(2)\n"
            "if args == ['info', '--cask', 'firefox']:\n"
            "    print('firefox: 130.0')\n"
            "    sys.exit(0)\n"
            "sys.exit(64)\n",
            encoding="utf-8",
        )
        stub.chmod(0o755)

        env = {
            "HOME": str(home),
            "ZDOTDIR": str(zdotdir),
            "ZSH": str(ROOT),
            "PATH": str(bin_dir),
            "HOMEBREW_PREFIX": str(prefix),
            "BREW_ARGV_LOG": str(argv_log),
            **{key: str(value) for key, value in paths.items()},
        }
        repository_before = git_state()
        actual = run([zsh, "-f", str(FIXTURE)], cwd=working, env=env)
        repository_after = git_state()
        argv = [json.loads(line) for line in argv_log.read_text().splitlines()] if argv_log.exists() else []

        expected_argv = [["info", "--cask"], ["info", "--cask", "firefox"]]
        require(actual.returncode == 0, f"fixture assertions failed with status {actual.returncode}: {actual.stderr}\n{actual.stdout}")
        require(argv == expected_argv, f"brew arguments differed: expected {expected_argv!r}; actual {argv!r}")
        require("failure_status=2" in actual.stdout, f"failure status missing: {actual.stdout!r}")
        require("Error: no cask name was provided (use: bci <cask>)" in actual.stdout, "failure diagnostic missing")
        require("success_status=0" in actual.stdout, f"success status missing: {actual.stdout!r}")
        require("success_stdout=firefox: 130.0" in actual.stdout, f"corrected output missing: {actual.stdout!r}")
        require("failure_stdout=" in actual.stdout and "success_stderr=" in actual.stdout, actual.stdout)
        fields = dict(line.split("=", 1) for line in actual.stdout.splitlines() if "=" in line)
        require(fields.get("before_pwd") == fields.get("after_failure_pwd") == fields.get("after_success_pwd"), "PWD changed during brew aliases")
        require(repository_before == repository_after, "repository state changed during the temporary shell fixture")

        print(f"PASS: bci-missing-cask | exit_status=2 | argv={argv[0]!r}")
        print(f"  diagnostic={fields.get('failure_stderr')!r}")
        print(f"PASS: bci-corrected-cask | exit_status=0 | argv={argv[1]!r}")
        print(f"  output={fields.get('success_stdout')!r}")
        print(
            "  shell_state: "
            f"before={fields['before_pwd']!r} after_failure={fields['after_failure_pwd']!r} "
            f"after_success={fields['after_success_pwd']!r}"
        )
        print(f"  repository_before={repository_before!r} repository_after={repository_after!r}")

        results = {
            "test_names": ["bci-missing-cask", "bci-corrected-cask"],
            "syntax_check": {"command": "zsh -n plugins/brew/brew.plugin.zsh", "exit_status": syntax.returncode},
            "expected": {
                "argv": expected_argv,
                "failure_status": 2,
                "failure_stderr": "Error: no cask name was provided (use: bci <cask>)",
                "success_status": 0,
                "success_stdout": "firefox: 130.0",
                "pwd": "unchanged",
            },
            "actual": {
                "fixture_exit_status": actual.returncode,
                "argv": argv,
                "stdout": actual.stdout,
                "stderr": actual.stderr,
                "state_before": fields.get("before_pwd"),
                "state_after_failure": fields.get("after_failure_pwd"),
                "state_after_success": fields.get("after_success_pwd"),
                "repository_before": repository_before,
                "repository_after": repository_after,
            },
            "tool_versions": {
                "python": sys.version.splitlines()[0],
                "zsh": run([zsh, "--version"], cwd=ROOT).stdout.strip(),
                "git": run(["git", "--version"], cwd=ROOT).stdout.strip(),
            },
        }
        (EVIDENCE / "inputs.json").write_text(
            json.dumps({"failure_command": ["bci"], "corrected_command": ["bci", "firefox"], "temp_path_contains_spaces": True}, indent=2) + "\n"
        )
        (EVIDENCE / "expected.json").write_text(json.dumps(results["expected"], indent=2) + "\n")
        (EVIDENCE / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        versions = results["tool_versions"]
        (EVIDENCE / "tool-versions.txt").write_text("\n".join(f"{key}: {value}" for key, value in versions.items()) + "\n")

    print("Native syntax check: exit 0; fixture cases executed: 2")
    print(f"Evidence saved under {EVIDENCE}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
