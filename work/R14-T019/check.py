#!/usr/bin/env python3
"""Check for R14-T019: run the docker plugin fixture test in an isolated zsh and verify failure propagation.

Usage: python3 work/R14-T019/check.py    (exit 0 only when every check holds)
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

TASK, ITEM = "R14-T019", "docker"
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
        broken_env = make_env(box, "broken")

        # Create a temporary broken plugin copy in the sandbox to prove failure propagation.
        orig_text = plugin.read_text()
        target = "alias dbl='docker build'"
        broken = "alias dbl='docker bild'"
        if target not in orig_text:
            sys.exit(f"FAIL: alias {target!r} not found in {plugin}")
        broken_text = orig_text.replace(target, broken, 1)
        broken_path = box / "broken.plugin.zsh"
        broken_path.write_text(broken_text)

        before = {"plugin_sha256": digest(plugin), "sandbox_real": tree(box / "real")}
        run = subprocess.run(
            [zsh, "-f", str(TEST), str(plugin)],
            cwd=box / "real",
            env=real_env,
            capture_output=True,
            text=True,
            timeout=120,
        )
        broken_run = subprocess.run(
            [zsh, "-f", str(TEST), str(broken_path)],
            cwd=box / "broken",
            env=broken_env,
            capture_output=True,
            text=True,
            timeout=120,
        )
        after = {"plugin_sha256": digest(plugin), "sandbox_real": tree(box / "real")}
    finally:
        shutil.rmtree(box, ignore_errors=True)

    out = run.stdout.replace(str(box), "<tmp>")
    err = run.stderr.replace(str(box), "<tmp>")
    broken_out = broken_run.stdout.replace(str(box), "<tmp>")
    broken_err = broken_run.stderr.replace(str(box), "<tmp>")

    cases = re.findall(r"^(PASS|FAIL): \[(success|edge)\] (.*)$", out, re.M)
    broken_cases = re.findall(r"^(PASS|FAIL): \[(success|edge)\] (.*)$", broken_out, re.M)
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
        "failure propagates on broken plugin": (
            broken_run.returncode != 0 and any(r == "FAIL" for r, _, _ in broken_cases)
        ),
        "plugin file unchanged": before["plugin_sha256"] == after["plugin_sha256"],
        "sandbox left clean": before["sandbox_real"] == after["sandbox_real"],
    }
    result = {
        "task": TASK,
        "item": ITEM,
        "command": f"zsh -f {TEST.relative_to(REPO)} {plugin.relative_to(REPO)}",
        "exit_status": run.returncode,
        "cases": [{"result": r, "kind": k, "name": n} for r, k, n in cases],
        "broken_plugin_check": {
            "exit_status": broken_run.returncode,
            "cases": [{"result": r, "kind": k, "name": n} for r, k, n in broken_cases],
            "stdout": broken_out,
            "stderr": broken_err,
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
    print(f"--- broken plugin check (exit={broken_run.returncode}) ---")
    print(broken_out, end="")
    for name, ok in checks.items():
        print(f"{'ok  ' if ok else 'FAIL'} {name}")
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
