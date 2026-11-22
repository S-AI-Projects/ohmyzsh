#!/usr/bin/env python3
"""
check.py – R14-T021: git-commit plugin test runner & assertion checker.

Usage:
    python3 work/R14-T021/check.py

Workflow:
  1. Runs `zsh -n plugins/git-commit/git-commit.plugin.zsh` (native repo check).
  2. Invokes work/R14-T021/run_tests.zsh to execute shell-level tests.
  3. Parses RESULT lines, pretty-prints each case, writes a JSON evidence file.
  4. Exits non-zero if ANY assertion fails or if no tests ran (zero-case guard).

Output files (all inside work/R14-T021/):
  - results.json   – machine-readable evidence (tool versions, inputs, outcomes)
"""

import json
import os
import platform
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR   = Path(__file__).resolve().parent
REPO_ROOT    = SCRIPT_DIR.parent.parent
PLUGIN_ZSH   = REPO_ROOT / "plugins" / "git-commit" / "git-commit.plugin.zsh"
HARNESS_ZSH  = SCRIPT_DIR / "run_tests.zsh"
RESULTS_JSON = SCRIPT_DIR / "results.json"

RESET  = "\033[0m"
GREEN  = "\033[32m"
RED    = "\033[31m"
YELLOW = "\033[33m"
BOLD   = "\033[1m"
CYAN   = "\033[36m"

def banner(msg: str) -> None:
    print(f"\n{BOLD}{CYAN}{'='*60}{RESET}")
    print(f"{BOLD}{CYAN}  {msg}{RESET}")
    print(f"{BOLD}{CYAN}{'='*60}{RESET}")

def status_line(name: str, status: str, notes: str = "") -> None:
    icon  = f"{GREEN}✔ PASS{RESET}" if status == "PASS" else f"{RED}✘ FAIL{RESET}"
    tail  = f"  {YELLOW}({notes}){RESET}" if notes else ""
    print(f"  {icon}  {name}{tail}")

# ── Step 0: Collect tool versions ────────────────────────────────────────────
def collect_versions() -> dict:
    versions: dict = {
        "python": platform.python_version(),
        "platform": platform.platform(),
    }
    for binary in ("zsh", "git"):
        try:
            out = subprocess.check_output([binary, "--version"],
                                          stderr=subprocess.STDOUT,
                                          text=True).strip().splitlines()[0]
            versions[binary] = out
        except Exception as exc:
            versions[binary] = f"error: {exc}"
    return versions

# ── Step 1: Native syntax check ───────────────────────────────────────────────
def run_syntax_check() -> dict:
    banner("Step 1 – Native repo check: zsh -n")
    start = time.monotonic()
    result = subprocess.run(
        ["zsh", "-n", str(PLUGIN_ZSH)],
        capture_output=True, text=True
    )
    elapsed = time.monotonic() - start
    passed  = result.returncode == 0
    print(f"  Command : zsh -n {PLUGIN_ZSH.relative_to(REPO_ROOT)}")
    print(f"  Exit    : {result.returncode}")
    print(f"  Stderr  : {result.stderr.strip() or '(none)'}")
    icon = f"{GREEN}OK{RESET}" if passed else f"{RED}FAIL{RESET}"
    print(f"  Result  : {icon}  ({elapsed:.3f}s)")
    if not passed:
        print(f"{RED}FATAL: plugin zsh -n check failed. Aborting.{RESET}")
        sys.exit(1)
    return {
        "name":     "zsh_syntax_check",
        "command":  f"zsh -n {PLUGIN_ZSH}",
        "exit":     result.returncode,
        "stderr":   result.stderr.strip(),
        "passed":   passed,
        "elapsed_s": round(elapsed, 4),
    }

# ── Step 2: Run the shell harness ─────────────────────────────────────────────
def run_shell_harness() -> tuple[list[dict], str]:
    banner("Step 2 – Shell test harness")
    print(f"  Harness : {HARNESS_ZSH.relative_to(REPO_ROOT)}")

    result = subprocess.run(
        ["zsh", str(HARNESS_ZSH)],
        capture_output=True, text=True,
        cwd=str(REPO_ROOT),
    )
    stdout = result.stdout.strip()
    stderr = result.stderr.strip()

    if result.returncode != 0:
        print(f"{RED}Shell harness exited {result.returncode}{RESET}")
        print(f"stdout:\n{stdout}")
        print(f"stderr:\n{stderr}")
        sys.exit(1)

    # Last line of stdout is the results-file path; preceding lines are RESULT|...
    lines = stdout.splitlines()
    results_file_path = ""
    result_lines: list[str] = []
    for line in lines:
        if line.startswith("RESULT|"):
            result_lines.append(line)
        elif line.startswith("/"):
            results_file_path = line   # the temp results file

    # Also try reading from the results file if path was returned
    if results_file_path and Path(results_file_path).exists():
        raw = Path(results_file_path).read_text().strip().splitlines()
        for line in raw:
            if line.startswith("RESULT|") and line not in result_lines:
                result_lines.append(line)

    test_results: list[dict] = []
    for line in result_lines:
        parts = line.split("|", 6)
        if len(parts) < 6:
            continue
        _, name, status, exit_code, actual, expected, *rest = parts
        notes = rest[0] if rest else ""
        test_results.append({
            "name":     name,
            "status":   status,
            "exit":     exit_code,
            "actual":   actual,
            "expected": expected,
            "notes":    notes,
        })

    if stderr:
        print(f"  Harness stderr:\n{stderr}")

    return test_results, stderr

# ── Step 3: Assert & report ───────────────────────────────────────────────────
def assert_results(test_results: list[dict]) -> bool:
    banner("Step 3 – Test assertions")

    if not test_results:
        print(f"{RED}FATAL: No test results recorded – zero-case run rejected.{RESET}")
        return False

    has_success = any(r["status"] == "PASS" for r in test_results)
    has_edge    = any(
        r["status"] == "PASS" and ("edge" in r.get("notes", "").lower()
                                   or "fail" in r["name"].lower()
                                   or "missing" in r["name"].lower()
                                   or "empty" in r["name"].lower()
                                   or "no_arg" in r["name"].lower()
                                   or "documented" in r.get("notes", "").lower())
        for r in test_results
    )
    all_passed  = all(r["status"] == "PASS" for r in test_results)

    for r in test_results:
        status_line(r["name"], r["status"], r.get("notes", ""))
        if r["status"] != "PASS":
            print(f"      actual  : {r['actual']!r}")
            print(f"      expected: {r['expected']!r}")

    print()
    total  = len(test_results)
    passed = sum(1 for r in test_results if r["status"] == "PASS")
    failed = total - passed
    print(f"  Total: {total}  |  {GREEN}Passed: {passed}{RESET}  |  {RED}Failed: {failed}{RESET}")

    # Required guards
    if not has_success:
        print(f"{RED}✘ At least one success case must pass.{RESET}")
        all_passed = False
    if not has_edge:
        print(f"{RED}✘ At least one documented failure/edge-state assertion must pass.{RESET}")
        all_passed = False

    return all_passed

# ── Step 4: Save evidence ─────────────────────────────────────────────────────
def save_evidence(versions: dict, syntax_result: dict, test_results: list[dict],
                  overall_passed: bool) -> None:
    evidence = {
        "task":         "R14-T021",
        "plugin":       "git-commit",
        "timestamp":    time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tool_versions": versions,
        "native_check": syntax_result,
        "tests":        test_results,
        "summary": {
            "total":   len(test_results),
            "passed":  sum(1 for r in test_results if r["status"] == "PASS"),
            "failed":  sum(1 for r in test_results if r["status"] == "FAIL"),
            "overall": "PASS" if overall_passed else "FAIL",
        },
    }
    RESULTS_JSON.write_text(json.dumps(evidence, indent=2))
    print(f"\n  Evidence saved → {RESULTS_JSON.relative_to(REPO_ROOT)}")

# ── Main ──────────────────────────────────────────────────────────────────────
def main() -> int:
    print(f"\n{BOLD}R14-T021 · git-commit plugin checks{RESET}")
    print(f"Repo root : {REPO_ROOT}")
    print(f"Plugin    : {PLUGIN_ZSH.relative_to(REPO_ROOT)}")

    versions       = collect_versions()
    syntax_result  = run_syntax_check()
    test_results, _= run_shell_harness()
    overall_passed = assert_results(test_results)
    save_evidence(versions, syntax_result, test_results, overall_passed)

    banner("Final verdict")
    if overall_passed:
        print(f"{BOLD}{GREEN}  ✔ ALL CHECKS PASSED{RESET}")
        return 0
    else:
        print(f"{BOLD}{RED}  ✘ ONE OR MORE CHECKS FAILED{RESET}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
