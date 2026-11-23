#!/usr/bin/env python3
"""
check.py – R14-T027: asdf plugin verified usage example and initialization runner.

Usage (from repo root):
    python3 work/R14-T027/check.py

Workflow:
  1. Runs `zsh -n plugins/asdf/asdf.plugin.zsh` (native repository syntax check).
  2. Invokes work/R14-T027/run_tests.zsh to execute shell-level initialization and usage tests.
  3. Validates the documented usage example against actual execution to prevent drift.
  4. Pretty-prints each test result and writes machine-readable evidence to results.json.
  5. Enforces zero-case guard and presence of edge/failure assertions.
"""

import json
import os
import platform
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR   = Path(__file__).resolve().parent
REPO_ROOT    = SCRIPT_DIR.parent.parent
PLUGIN_ZSH   = REPO_ROOT / "plugins" / "asdf" / "asdf.plugin.zsh"
HARNESS_ZSH  = SCRIPT_DIR / "run_tests.zsh"
RESULTS_JSON = SCRIPT_DIR / "results.json"

RESET  = "\033[0m"
GREEN  = "\033[32m"
RED    = "\033[31m"
YELLOW = "\033[33m"
BOLD   = "\033[1m"
CYAN   = "\033[36m"

def banner(msg: str):
    print(f"\n{BOLD}{CYAN}{'='*60}{RESET}")
    print(f"{BOLD}{CYAN}  {msg}{RESET}")
    print(f"{BOLD}{CYAN}{'='*60}{RESET}")

def status_line(name: str, status: str, notes: str = ""):
    icon = f"{GREEN}✔ PASS{RESET}" if status == "PASS" else f"{RED}✘ FAIL{RESET}"
    tail = f"  {YELLOW}({notes}){RESET}" if notes else ""
    print(f"  {icon}  {name}{tail}")

def collect_versions() -> dict:
    versions = {
        "python": platform.python_version(),
        "platform": platform.platform(),
    }
    for b in ("zsh", "git"):
        try:
            out = subprocess.check_output([b, "--version"], stderr=subprocess.STDOUT, text=True)
            versions[b] = out.strip().splitlines()[0]
        except Exception as e:
            versions[b] = f"error: {e}"
    return versions

def run_syntax_check() -> dict:
    banner("Step 1 – Native repo check: zsh -n")
    t0 = time.monotonic()
    r = subprocess.run(["zsh", "-n", str(PLUGIN_ZSH)], capture_output=True, text=True)
    elapsed = time.monotonic() - t0
    passed = (r.returncode == 0)
    print(f"  Command : zsh -n {PLUGIN_ZSH.relative_to(REPO_ROOT)}")
    print(f"  Exit    : {r.returncode}")
    print(f"  Stderr  : {r.stderr.strip() or '(none)'}")
    print(f"  Result  : {GREEN+'OK'+RESET if passed else RED+'FAIL'+RESET}  ({elapsed:.3f}s)")
    if not passed:
        print(f"{RED}FATAL: asdf plugin syntax check failed.{RESET}")
        sys.exit(1)
    return {
        "name": "zsh_syntax_check",
        "command": f"zsh -n {PLUGIN_ZSH}",
        "exit": r.returncode,
        "stderr": r.stderr.strip(),
        "passed": passed,
        "elapsed_s": round(elapsed, 4)
    }

def run_shell_harness() -> list[dict]:
    banner("Step 2 – Shell test harness (Usage Example & Initialization)")
    print(f"  Harness : {HARNESS_ZSH.relative_to(REPO_ROOT)}")
    r = subprocess.run(["zsh", str(HARNESS_ZSH)], capture_output=True, text=True, cwd=str(REPO_ROOT))
    if r.returncode != 0:
        print(f"{RED}Shell harness exited with code {r.returncode}{RESET}")
        print(r.stdout)
        print(r.stderr)
        sys.exit(1)

    results = []
    for line in r.stdout.splitlines():
        if not line.startswith("RESULT|"):
            continue
        parts = line.split("|", 6)
        if len(parts) < 6:
            continue
        _, name, status, exit_code, actual, expected, *rest = parts
        results.append({
            "name": name,
            "status": status,
            "exit": exit_code,
            "actual": actual,
            "expected": expected,
            "notes": rest[0] if rest else ""
        })
    return results

def assert_results(results: list[dict]) -> bool:
    banner("Step 3 – Test assertions & verification")
    if not results:
        print(f"{RED}FATAL: Zero tests recorded – zero-case run rejected.{RESET}")
        return False

    has_success = any(r["status"] == "PASS" for r in results)
    edge_keywords = ("edge", "failure", "missing", "isolation", "deduplicated")
    has_edge = any(
        r["status"] == "PASS" and
        any(kw in r["name"].lower() or kw in r.get("notes", "").lower() for kw in edge_keywords)
        for r in results
    )
    all_passed = all(r["status"] == "PASS" for r in results)

    for r in results:
        status_line(r["name"], r["status"], r.get("notes", ""))
        if r["status"] != "PASS":
            print(f"      actual  : {r['actual']!r}")
            print(f"      expected: {r['expected']!r}")

    total = len(results)
    passed = sum(1 for r in results if r["status"] == "PASS")
    failed = total - passed
    print(f"\n  Total: {total}  |  {GREEN}Passed: {passed}{RESET}  |  {RED}Failed: {failed}{RESET}")

    if not has_success:
        print(f"{RED}✘ At least one success case must pass.{RESET}")
        all_passed = False
    if not has_edge:
        print(f"{RED}✘ At least one edge/failure-state assertion must pass.{RESET}")
        all_passed = False

    return all_passed

def save_evidence(versions: dict, syntax_result: dict, results: list[dict], overall: bool):
    ev = {
        "task": "R14-T027",
        "plugin": "asdf",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tool_versions": versions,
        "native_check": syntax_result,
        "tests": results,
        "summary": {
            "total": len(results),
            "passed": sum(1 for r in results if r["status"] == "PASS"),
            "failed": sum(1 for r in results if r["status"] == "FAIL"),
            "overall": "PASS" if overall else "FAIL",
        },
    }
    RESULTS_JSON.write_text(json.dumps(ev, indent=2))
    print(f"\n  Evidence saved → {RESULTS_JSON.relative_to(REPO_ROOT)}")

def main():
    print(f"\n{BOLD}R14-T027 · asdf plugin checks{RESET}")
    print(f"Repo root : {REPO_ROOT}")
    print(f"Plugin    : {PLUGIN_ZSH.relative_to(REPO_ROOT)}")

    versions      = collect_versions()
    syntax_result = run_syntax_check()
    results       = run_shell_harness()
    overall       = assert_results(results)
    save_evidence(versions, syntax_result, results, overall)

    banner("Final verdict")
    if overall:
        print(f"{BOLD}{GREEN}  ✔ ALL CHECKS PASSED{RESET}")
        return 0
    print(f"{BOLD}{RED}  ✘ ONE OR MORE CHECKS FAILED{RESET}")
    return 1

if __name__ == "__main__":
    sys.exit(main())
