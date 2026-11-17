#!/usr/bin/env python3
"""Run isolated man widget quoting checks and save their evidence."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
PLUGIN = ROOT / "plugins/man/man.plugin.zsh"
TEST = ROOT / "plugins/man/tests/man.test.zsh"
CASES = {
    "matched-wildcard": "quoted path with spaces and matching wildcard remains one literal argument",
    "unmatched-wildcard": "quoted path with spaces and unmatched wildcard remains one literal argument",
}


def run(args: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          check=False)


def snapshot(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): path.read_text()
        for path in sorted(root.rglob("*")) if path.is_file()
    }


def main() -> int:
    repository_before = run(["git", "status", "--porcelain=v1"]).stdout.splitlines()
    zsh_version = run(["zsh", "--version"])
    syntax = run(["zsh", "-n", str(PLUGIN)])
    actual_cases: list[dict[str, object]] = []
    errors: list[str] = []

    for case, assertion in CASES.items():
        with tempfile.TemporaryDirectory(prefix=f"man-{case}-") as temp_root:
            temp = Path(temp_root)
            work_dir = temp / "working directory with spaces"
            manual_dir = work_dir / "manual files"
            stub_dir = temp / "bin"
            zdotdir = temp / "zdotdir"
            manual_dir.mkdir(parents=True)
            stub_dir.mkdir()
            zdotdir.mkdir()
            (work_dir / "unrelated.txt").write_text("must remain unchanged\n")
            if case == "matched-wildcard":
                (manual_dir / "first.md").write_text("first manual\n")
                (manual_dir / "second.md").write_text("second manual\n")

            stub = stub_dir / "man"
            stub.write_text(
                "#!/bin/zsh\n"
                "print -r -- BEGIN >> \"$ANT_TEST_LOG\"\n"
                "print -r -- \"COUNT:$#\" >> \"$ANT_TEST_LOG\"\n"
                "for arg in \"$@\"; do print -r -- \"${(qqq)arg}\" >> \"$ANT_TEST_LOG\"; done\n"
                "print -r -- stub-man-output\n"
                "exit 0\n"
            )
            stub.chmod(0o755)

            before = snapshot(work_dir)
            env = os.environ.copy()
            env.update({
                "ANT_TEST_ROOT": str(temp),
                "ANT_TEST_WORK_DIR": str(work_dir),
                "ZDOTDIR": str(zdotdir),
                "PATH": f"{stub_dir}{os.pathsep}{env.get('PATH', '/usr/bin:/bin')}",
            })
            result = run(["zsh", "-f", str(TEST), case, str(ROOT), str(work_dir)], env=env)
            after = snapshot(work_dir)
        pass_lines = [line for line in result.stdout.splitlines()
                      if line.startswith(f"PASS: {case} |")]
        valid = result.returncode == 0 and len(pass_lines) == 1 and before == after
        if not valid:
            errors.append(f"{case}: expected one passing assertion, unchanged files, and exit 0; got exit {result.returncode}")
        actual_cases.append({
            "case": case,
            "expected_assertion": assertion,
            "exit_status": result.returncode,
            "passed_named_assertion": len(pass_lines) == 1,
            "workspace_files_before": before,
            "workspace_files_after": after,
            "workspace_unchanged": before == after,
            "output": result.stdout,
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
        "runner": "python3 work/R14-T004/check.py",
        "invocation": "zsh -f with temporary ZDOTDIR and a temporary working directory containing spaces",
        "command_stub": "temporary PATH entry named man; no system man pages are opened",
        "arguments": ["viewer", "manual files/*.md"],
        "protected_state": "temporary workspace file names and contents before/after widget and command execution",
    }
    expected = {
        "syntax_exit_status": 0,
        "assertions": list(CASES.values()),
        "case_count": len(CASES),
        "argument_boundaries_preserved": True,
        "wildcards_not_expanded": True,
        "unrelated_files_unchanged": True,
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
