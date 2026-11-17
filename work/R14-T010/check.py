#!/usr/bin/env python3
"""Characterize the tldr widget and prove it rejects a one-condition mutant."""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
EVIDENCE = pathlib.Path(__file__).resolve().parent
PLUGIN = ROOT / "plugins/tldr/tldr.plugin.zsh"
FIXTURE = ROOT / "plugins/tldr/tests/tldr.test.zsh"
MUTANT_FROM = '[[ "$BUFFER" = tldr\\ * ]] && return'
MUTANT_TO = '[[ "$BUFFER" = tldr* ]] && return'


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


def execute_case(
    zsh: str,
    *,
    name: str,
    plugin_file: pathlib.Path,
    input_buffer: str,
    expected_buffer: str,
    history_buffer: str = "",
    expected_exit: int = 0,
) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix=f"tldr-{name}-") as temp:
        base = pathlib.Path(temp)
        home, zdotdir, cwd, bin_dir = (base / part for part in ("home", "zdotdir", "working directory with spaces", "bin"))
        for directory in (home, zdotdir, cwd, bin_dir):
            directory.mkdir(parents=True, exist_ok=True)
        env = {
            "HOME": str(home),
            "ZDOTDIR": str(zdotdir),
            "ZSH": str(ROOT),
            "PATH": str(bin_dir),
            "TLDR_PLUGIN_FILE": str(plugin_file),
            "TLDR_TEST_CASE": name,
            "TLDR_INPUT_BUFFER": input_buffer,
            "TLDR_EXPECTED_BUFFER": expected_buffer,
            "TLDR_HISTORY_BUFFER": history_buffer,
        }
        repository_before = git_state()
        actual = run([zsh, "-f", str(FIXTURE)], cwd=cwd, env=env)
        repository_after = git_state()
        require(repository_before == repository_after, f"repository state changed in {name}")
        fields = dict(line.split("=", 1) for line in actual.stdout.splitlines() if "=" in line)
        if expected_exit == 0:
            require(actual.returncode == 0, f"{name} failed ({actual.returncode}):\n{actual.stdout}\n{actual.stderr}")
            require(fields.get("after_buffer") == expected_buffer, f"{name} produced wrong BUFFER: {actual.stdout!r}")
        else:
            require(actual.returncode == expected_exit, f"mutant was not rejected as expected: exit={actual.returncode}, output={actual.stdout!r}, stderr={actual.stderr!r}")
            require("BUFFER assertion failed" in actual.stderr, f"mutant failed for an unrelated reason: {actual.stderr!r}")
        require(fields.get("before_pwd") == fields.get("after_pwd"), f"PWD changed in {name}: {actual.stdout!r}")
        require(fields.get("before_path") == fields.get("after_path"), f"PATH changed in {name}: {actual.stdout!r}")
    require(not base.exists(), f"temporary state not removed in {name}: {base}")
    result = {
        "name": name,
        "input": {"BUFFER": input_buffer, "history_buffer": history_buffer},
        "expected": {"BUFFER": expected_buffer, "fixture_exit_status": expected_exit},
        "actual": {
            "fixture_exit_status": actual.returncode,
            "stdout": actual.stdout,
            "stderr": actual.stderr,
            "state_before": {"BUFFER": fields.get("before_buffer"), "PWD": fields.get("before_pwd"), "PATH": fields.get("before_path")},
            "state_after": {"BUFFER": fields.get("after_buffer"), "PWD": fields.get("after_pwd"), "PATH": fields.get("after_path")},
            "repository_before": repository_before,
            "repository_after": repository_after,
            "temporary_directory_removed": True,
        },
    }
    print(f"PASS: {name} | fixture_exit_status={actual.returncode} | BUFFER={fields.get('before_buffer')!r} -> {fields.get('after_buffer')!r}")
    print(f"  PWD={fields.get('before_pwd')!r} -> {fields.get('after_pwd')!r}; PATH unchanged={fields.get('before_path') == fields.get('after_path')}")
    print(f"  stderr={actual.stderr.rstrip()!r}; repository_before={repository_before!r} repository_after={repository_after!r}")
    return result


def main() -> int:
    zsh = shutil.which("zsh")
    require(zsh is not None, "zsh is required")
    require(PLUGIN.is_file() and FIXTURE.is_file(), "plugin or fixture is missing")
    syntax = run([zsh, "-n", str(PLUGIN)], cwd=ROOT)
    require(syntax.returncode == 0, f"plugin syntax check failed: {syntax.stderr}")

    results = [
        execute_case(zsh, name="normal-command", plugin_file=PLUGIN, input_buffer="git status", expected_buffer="tldr git"),
        execute_case(zsh, name="existing-tldr-prefix", plugin_file=PLUGIN, input_buffer="tldr --help", expected_buffer="tldr --help"),
        execute_case(zsh, name="empty-buffer-history", plugin_file=PLUGIN, input_buffer="", history_buffer="git status", expected_buffer="tldr git"),
    ]

    with tempfile.TemporaryDirectory(prefix="tldr-mutant-") as temp:
        mutant_dir = pathlib.Path(temp)
        mutant = mutant_dir / "tldr.plugin.zsh"
        source = PLUGIN.read_text(encoding="utf-8")
        require(source.count(MUTANT_FROM) == 1, "expected exactly one condition to mutate")
        mutant.write_text(source.replace(MUTANT_FROM, MUTANT_TO, 1), encoding="utf-8")
        require(mutant.read_text(encoding="utf-8") != source, "temporary mutant was not introduced")
        mutant_result = execute_case(
            zsh,
            name="mutant-rejected-tldrish",
            plugin_file=mutant,
            input_buffer="tldrish",
            expected_buffer="tldr tldrish",
            expected_exit=42,
        )
        results.append(mutant_result)
    require(not mutant_dir.exists(), "temporary mutant source was not cleaned up")
    expected_names = ["normal-command", "existing-tldr-prefix", "empty-buffer-history", "mutant-rejected-tldrish"]
    require([result["name"] for result in results] == expected_names, "zero-case or incomplete regression run is rejected")

    versions = {
        "python": sys.version.splitlines()[0],
        "zsh": run([zsh, "--version"], cwd=ROOT).stdout.strip(),
        "git": run(["git", "--version"], cwd=ROOT).stdout.strip(),
    }
    evidence = {
        "test_names": expected_names,
        "syntax_check": {"command": "zsh -n plugins/tldr/tldr.plugin.zsh", "exit_status": syntax.returncode},
        "mutant": {"condition_before": MUTANT_FROM, "condition_after": MUTANT_TO, "mutation_is_temporary": True},
        "cases": results,
        "tool_versions": versions,
    }
    (EVIDENCE / "inputs.json").write_text(json.dumps({"normal": "git status", "existing_prefix": "tldr --help", "history": "git status", "mutant_reject_input": "tldrish"}, indent=2) + "\n")
    (EVIDENCE / "expected.json").write_text(json.dumps({"cases": [{"name": result["name"], **result["expected"]} for result in results]}, indent=2) + "\n")
    (EVIDENCE / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    (EVIDENCE / "tool-versions.txt").write_text("\n".join(f"{key}: {value}" for key, value in versions.items()) + "\n")
    print(f"Native syntax check: exit {syntax.returncode}; test cases executed: {len(results)}")
    print(f"Evidence saved under {EVIDENCE}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
