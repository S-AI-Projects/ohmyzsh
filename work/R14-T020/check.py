#!/usr/bin/env python3
"""Check for R14-T020: run npm plugin regression tests and reject a one-condition mutant.

Usage: python3 work/R14-T020/check.py    (exit 0 only when every check holds)
"""
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TASK, ITEM = "R14-T020", "npm"
HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
PLUGIN = REPO / "plugins" / ITEM / f"{ITEM}.plugin.zsh"
TEST = REPO / "plugins" / ITEM / "tests" / f"{ITEM}.test.zsh"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree(root: Path) -> list[str]:
    return sorted(str(p.relative_to(root)) for p in Path(root).rglob("*"))


def make_env(box: Path, sub: str) -> dict[str, str]:
    env = {
        "HOME": f"{box}/{sub}/home",
        "ZDOTDIR": f"{box}/{sub}/zdot",
        "TMPDIR": f"{box}/{sub}/tmp",
        "ZSH_CACHE_DIR": f"{box}/{sub}/cache",
        "ZSH": str(REPO),
        "PATH": "/usr/bin:/bin",
        "LC_ALL": "C",
        "TERM": "dumb",
    }
    for key in ("HOME", "ZDOTDIR", "TMPDIR", "ZSH_CACHE_DIR"):
        os.makedirs(env[key], exist_ok=True)
    return env


def main(plugin: Path = PLUGIN) -> int:
    zsh = shutil.which("zsh")
    if not zsh:
        sys.exit("FAIL: zsh is not installed")

    box = Path(tempfile.mkdtemp(prefix=f"{TASK}-")).resolve()
    try:
        real_env = make_env(box, "real")
        mut_env = make_env(box, "mutant")

        # Create temporary one-condition mutant inside the sandbox (never touches repo files).
        orig_text = plugin.read_text()
        target = "(( $+commands[npm] )) && {"
        mutated = "(( ! $+commands[npm] )) && {"
        if target not in orig_text:
            sys.exit(f"FAIL: condition {target!r} not found in {plugin}")
        mut_text = orig_text.replace(target, mutated, 1)
        orig_lines = orig_text.splitlines()
        mut_lines = mut_text.splitlines()
        diff_lines = [
            i + 1
            for i, (a, b) in enumerate(zip(orig_lines, mut_lines))
            if a != b
        ]
        mutant_path = box / "mutant.plugin.zsh"
        mutant_path.write_text(mut_text)

        before = {"plugin_sha256": digest(plugin), "sandbox_real": tree(box / "real")}
        run = subprocess.run(
            [zsh, "-f", str(TEST), str(plugin)],
            cwd=box / "real",
            env=real_env,
            capture_output=True,
            text=True,
            timeout=120,
        )
        mut_run = subprocess.run(
            [zsh, "-f", str(TEST), str(mutant_path)],
            cwd=box / "mutant",
            env=mut_env,
            capture_output=True,
            text=True,
            timeout=120,
        )
        after = {"plugin_sha256": digest(plugin), "sandbox_real": tree(box / "real")}
    finally:
        shutil.rmtree(box, ignore_errors=True)

    out = run.stdout.replace(str(box), "<tmp>")
    err = run.stderr.replace(str(box), "<tmp>")
    mut_out = mut_run.stdout.replace(str(box), "<tmp>")
    mut_err = mut_run.stderr.replace(str(box), "<tmp>")

    cases = re.findall(r"^(PASS|FAIL): \[(success|edge)\] (.*)$", out, re.M)
    mut_cases = re.findall(r"^(PASS|FAIL): \[(success|edge)\] (.*)$", mut_out, re.M)
    summary_match = re.search(r"^(\d+) tests, (\d+) failures$", out, re.M)

    checks = {
        "test exited 0": run.returncode == 0,
        "at least one case ran": len(cases) > 0,
        "summary count matches cases": (
            summary_match is not None
            and int(summary_match.group(1)) == len(cases)
            and int(summary_match.group(2)) == 0
        ),
        "no case failed": all(result == "PASS" for result, _, _ in cases),
        "no unexpected stderr": err == "",
        "a success case ran": any(kind == "success" for _, kind, _ in cases),
        "a failure or edge case ran": any(kind == "edge" for _, kind, _ in cases),
        "mutant differs on exactly 1 line": len(orig_lines) == len(mut_lines) and len(diff_lines) == 1,
        "mutant rejected (non-zero exit)": mut_run.returncode != 0 and any(r == "FAIL" for r, _, _ in mut_cases),
        "plugin file unchanged": before["plugin_sha256"] == after["plugin_sha256"],
        "sandbox left clean": before["sandbox_real"] == after["sandbox_real"],
    }
    result = {
        "task": TASK,
        "item": ITEM,
        "command": f"zsh -f {TEST.relative_to(REPO)} {plugin.relative_to(REPO)}",
        "exit_status": run.returncode,
        "cases": [{"result": r, "kind": k, "name": n} for r, k, n in cases],
        "mutant_check": {
            "diff_line_numbers": diff_lines,
            "exit_status": mut_run.returncode,
            "cases": [{"result": r, "kind": k, "name": n} for r, k, n in mut_cases],
            "stdout": mut_out,
            "stderr": mut_err,
        },
        "checks": checks,
        "state_before": before,
        "state_after": after,
        "stdout": out,
        "stderr": err,
    }
    (HERE / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    zsh_version = subprocess.run(
        [zsh, "--version"], capture_output=True, text=True
    ).stdout.strip()
    (HERE / "versions.txt").write_text(
        f"{zsh_version}\npython {platform.python_version()}\n{platform.platform()}\n"
    )

    print(out, end="")
    print(f"--- mutant check (exit={mut_run.returncode}) ---")
    print(mut_out, end="")
    for name, ok in checks.items():
        print(f"{'ok  ' if ok else 'FAIL'} {name}")
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
