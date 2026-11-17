#!/usr/bin/env python3
"""Repeatable, service-independent checks for the JFrog Zsh plugin."""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
EVIDENCE = pathlib.Path(__file__).resolve().parent
PLUGIN = ROOT / "plugins/jfrog/jfrog.plugin.zsh"
FIXTURE = ROOT / "plugins/jfrog/tests/jfrog.test.zsh"


def run(command: list[str], *, cwd: pathlib.Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True, check=False)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def git_state() -> list[str]:
    result = run(["git", "status", "--short"], cwd=ROOT)
    if result.returncode:
        raise AssertionError(f"git status failed: {result.stderr}")
    return result.stdout.splitlines()


def main() -> int:
    zsh = shutil.which("zsh")
    require(zsh is not None, "zsh is required")
    require(PLUGIN.is_file() and FIXTURE.is_file(), "plugin or Zsh fixture is missing")
    syntax = run([zsh, "-n", str(PLUGIN)], cwd=ROOT)
    require(syntax.returncode == 0, f"plugin syntax check failed: {syntax.stderr}")

    expected_cases = ["success", "cli-failure"]
    cases: list[dict[str, object]] = []
    for case_name in expected_cases:
        with tempfile.TemporaryDirectory(prefix=f"jfrog-{case_name}-") as temp:
            base = pathlib.Path(temp)
            home = base / "home"
            zdotdir = base / "zdotdir"
            cwd = base / "working directory with spaces"
            bin_dir = base / "bin"
            for directory in (home, zdotdir, cwd, bin_dir):
                directory.mkdir(parents=True, exist_ok=True)
            argv_log = base / "jfrog-calls.jsonl"
            stderr_capture = base / "completion.stderr"

            stub = bin_dir / "jfrog"
            stub.write_text(
                "#!" + sys.executable + "\n"
                "import json, os, sys\n"
                "args = sys.argv[1:]\n"
                "mode = os.environ['JFROG_TEST_CASE']\n"
                "status = 19 if mode == 'cli-failure' else 0\n"
                "with open(os.environ['JFROG_ARGV_LOG'], 'a') as log:\n"
                "    log.write(json.dumps({'argv': args, 'exit_status': status}) + '\\n')\n"
                "if args != ['--generate-bash-completion']:\n"
                "    print('unexpected JFrog arguments', file=sys.stderr)\n"
                "    sys.exit(64)\n"
                "if mode == 'success':\n"
                "    print('repo-one\\nrepo two')\n"
                "else:\n"
                "    print('simulated JFrog CLI failure', file=sys.stderr)\n"
                "sys.exit(status)\n",
                encoding="utf-8",
            )
            stub.chmod(0o755)

            env = {
                "HOME": str(home),
                "ZDOTDIR": str(zdotdir),
                "ZSH": str(ROOT),
                "PATH": str(bin_dir),
                "JFROG_TEST_CASE": case_name,
                "JFROG_ARGV_LOG": str(argv_log),
                "JFROG_TEST_STDERR": str(stderr_capture),
                "JFROG_FILES_STATUS": "0",
            }
            repository_before = git_state()
            actual = run([zsh, "-f", str(FIXTURE)], cwd=cwd, env=env)
            repository_after = git_state()
            logs = [json.loads(line) for line in argv_log.read_text().splitlines()] if argv_log.exists() else []
            expected_log = [{"argv": ["--generate-bash-completion"], "exit_status": 19 if case_name == "cli-failure" else 0}]
            require(actual.returncode == 0, f"{case_name} fixture exited {actual.returncode}:\n{actual.stdout}\n{actual.stderr}")
            require(logs == expected_log, f"{case_name} JFrog argv/status mismatch: {logs!r}")
            require(repository_before == repository_after, f"repository changed during {case_name}")

            fields = dict(line.split("=", 1) for line in actual.stdout.splitlines() if "=" in line)
            require(fields.get("case") == case_name, f"case marker mismatch: {actual.stdout!r}")
            require(fields.get("before_pwd") == fields.get("after_pwd"), f"PWD changed: {actual.stdout!r}")
            require(fields.get("before_path") == fields.get("after_path"), f"PATH changed: {actual.stdout!r}")
            if case_name == "success":
                require(fields.get("completion_status") == "0", actual.stdout)
                require(fields.get("candidate_count") == "2", actual.stdout)
                require("candidate=repo-one" in actual.stdout and "candidate=repo two" in actual.stdout, actual.stdout)
                require(fields.get("file_calls") == "0", actual.stdout)
                require(fields.get("completion_stderr") == "", actual.stdout)
            else:
                require(fields.get("completion_status") == "23", actual.stdout)
                require(fields.get("candidate_count") == "0", actual.stdout)
                require(fields.get("file_calls") == "1", actual.stdout)
                require(fields.get("completion_stderr") == "simulated JFrog CLI failure", actual.stdout)

            print(
                f"PASS: {case_name} | fixture_exit_status={actual.returncode} "
                f"| jfrog_argv={logs[0]['argv']!r} | jfrog_exit_status={logs[0]['exit_status']} "
                f"| completion_status={fields.get('completion_status')}"
            )
            print(f"  output={actual.stdout.rstrip()!r}")
            print(f"  repository_before={repository_before!r} repository_after={repository_after!r}")
            cases.append(
                {
                    "name": case_name,
                    "input": {"cwd": str(cwd), "path": str(bin_dir), "zdotdir": str(zdotdir)},
                    "expected": {"jfrog": expected_log[0], "fixture_exit_status": 0},
                    "actual": {
                        "jfrog": logs[0],
                        "fixture_exit_status": actual.returncode,
                        "completion_status": int(fields["completion_status"]),
                        "stdout": actual.stdout,
                        "stderr": actual.stderr,
                        "state_before": {"PWD": fields["before_pwd"], "PATH": fields["before_path"]},
                        "state_after": {"PWD": fields["after_pwd"], "PATH": fields["after_path"]},
                        "repository_before": repository_before,
                        "repository_after": repository_after,
                    },
                }
            )
        require(not base.exists(), f"temporary state was not cleaned up for {case_name}: {base}")

    require(cases and [case["name"] for case in cases] == expected_cases, "zero-case or incomplete run is rejected")
    versions = {
        "python": sys.version.splitlines()[0],
        "zsh": run([zsh, "--version"], cwd=ROOT).stdout.strip(),
        "git": run(["git", "--version"], cwd=ROOT).stdout.strip(),
    }
    results = {
        "test_names": expected_cases,
        "syntax_check": {"command": "zsh -n plugins/jfrog/jfrog.plugin.zsh", "exit_status": syntax.returncode},
        "cases": cases,
        "tool_versions": versions,
        "cleanup": "Temporary HOME, ZDOTDIR, PATH, working directory, stub CLI, and logs removed by TemporaryDirectory.",
    }
    (EVIDENCE / "inputs.json").write_text(json.dumps({"cases": expected_cases, "services": "not required"}, indent=2) + "\n")
    (EVIDENCE / "expected.json").write_text(json.dumps({"cases": [case["expected"] for case in cases]}, indent=2) + "\n")
    (EVIDENCE / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    (EVIDENCE / "tool-versions.txt").write_text("\n".join(f"{key}: {value}" for key, value in versions.items()) + "\n")
    print(f"Native syntax check: exit {syntax.returncode}; fixture cases executed: {len(cases)}")
    print(f"Evidence saved under {EVIDENCE}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
