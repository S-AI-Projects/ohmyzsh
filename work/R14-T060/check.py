#!/usr/bin/env python3
"""
Automated check script for Oh My Zsh task R14-T060:
Protect a condition with a regression: gcloud [plugins/gcloud]
Issue: https://github.com/S-AI-Projects/ohmyzsh/issues/60
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone


def run_command(cmd, env=None, cwd=None):
    """Run a command and return (returncode, stdout, stderr)."""
    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        cwd=cwd,
    )
    return proc.returncode, proc.stdout, proc.stderr


def get_tool_versions(repo_root):
    """Collect runtime tool versions and repository state."""
    versions = {}

    # Zsh version
    rc, out, _ = run_command(["zsh", "--version"])
    versions["zsh"] = out.strip() if rc == 0 else "unknown"

    # Python version
    versions["python"] = sys.version.replace("\n", " ")

    # Git commit
    rc, out, _ = run_command(["git", "rev-parse", "HEAD"], cwd=repo_root)
    versions["git_commit"] = out.strip() if rc == 0 else "unknown"

    # Git branch
    rc, out, _ = run_command(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_root)
    versions["git_branch"] = out.strip() if rc == 0 else "unknown"

    return versions


def parse_test_output(stdout, stderr):
    """Parse test output from gcloud.test.zsh into structured test objects."""
    tests = []
    lines = stdout.splitlines() + stderr.splitlines()
    for line in lines:
        m = re.match(r"^(PASS|FAIL)\s+\[([^\]]+)\]\s+(.*)$", line.strip())
        if m:
            status, name, desc = m.groups()
            tests.append({
                "name": name,
                "status": status,
                "description": desc,
            })
    return tests


def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    work_dir = os.path.join(repo_root, "work", "R14-T060")
    os.makedirs(work_dir, exist_ok=True)

    print("=================================================================")
    print(" Running R14-T060 Verification Harness: gcloud regression check  ")
    print("=================================================================")

    # Stage 1: Plugin syntax validation
    plugin_rel = "plugins/gcloud/gcloud.plugin.zsh"
    plugin_path = os.path.join(repo_root, plugin_rel)
    test_rel = "plugins/gcloud/tests/gcloud.test.zsh"
    test_path = os.path.join(repo_root, test_rel)

    print(f"\n[1/6] Validating plugin syntax: zsh -n {plugin_rel}")
    rc, out, err = run_command(["zsh", "-n", plugin_path])
    if rc != 0:
        print(f"ERROR: Plugin syntax check failed:\n{err}", file=sys.stderr)
        sys.exit(rc)
    print("  -> Syntax check passed cleanly.")

    # Stage 2: Tool versions recording
    print("\n[2/6] Recording environment and runtime tool versions")
    tool_versions = get_tool_versions(repo_root)
    for k, v in tool_versions.items():
        print(f"  {k}: {v}")

    # Condition Details
    condition_details = {
        "source_file": plugin_rel,
        "line_number": 35,
        "original_condition": 'if [[ -f "${CLOUDSDK_HOME}/path.zsh.inc" ]]; then',
        "mutated_condition": 'if [[ ! -f "${CLOUDSDK_HOME}/path.zsh.inc" ]]; then',
        "mutation_type": "Condition inversion (negating regular file check -f to ! -f)",
        "purpose": "Guards execution of SDK path.zsh.inc so SDK binaries are added to PATH only when file exists",
        "protected_behavior": "When CLOUDSDK_HOME contains path.zsh.inc, it is sourced to configure PATH and environment",
        "expected_failure_when_mutated": "When mutated with [[ ! -f ... ]], existing path.zsh.inc is skipped, leaving PATH unmodified and failing regression assertion T10",
    }

    # Stage 3: Scenario A — Original implementation test run
    print("\n[3/6] Scenario A: Executing regression test against ORIGINAL implementation")
    rc_orig, stdout_orig, stderr_orig = run_command(["zsh", "-df", test_path], cwd=repo_root)
    print(stdout_orig.strip())
    if stderr_orig.strip():
        print(stderr_orig.strip(), file=sys.stderr)

    orig_tests = parse_test_output(stdout_orig, stderr_orig)
    if len(orig_tests) == 0:
        print("ERROR: Zero tests detected in test run; rejecting zero-case run.", file=sys.stderr)
        sys.exit(1)

    failed_orig = [t for t in orig_tests if t["status"] == "FAIL"]
    if rc_orig != 0 or failed_orig:
        print(f"ERROR: Original implementation failed {len(failed_orig)} tests!", file=sys.stderr)
        sys.exit(1)
    print(f"  -> Original implementation PASSED all {len(orig_tests)} tests.")

    # Stage 4: Scenario B — Temporary one-condition mutant experiment
    print("\n[4/6] Scenario B: Creating temporary one-condition mutant and verifying REJECTION")
    temp_dir = tempfile.mkdtemp(prefix="gcloud_mutant_")
    mutant_path = os.path.join(temp_dir, "gcloud.plugin.zsh")

    try:
        with open(plugin_path, "r", encoding="utf-8") as f:
            plugin_content = f.read()

        orig_cond = condition_details["original_condition"]
        mut_cond = condition_details["mutated_condition"]

        if orig_cond not in plugin_content:
            print(f"ERROR: Original condition '{orig_cond}' not found in {plugin_path}", file=sys.stderr)
            sys.exit(1)

        mutated_content = plugin_content.replace(orig_cond, mut_cond, 1)

        # Verify exactly one condition modified
        orig_lines = plugin_content.splitlines()
        mut_lines = mutated_content.splitlines()
        diff_lines = [i for i, (l1, l2) in enumerate(zip(orig_lines, mut_lines)) if l1 != l2]
        if len(diff_lines) != 1:
            print(f"ERROR: Expected exactly 1 line modified, found {len(diff_lines)}", file=sys.stderr)
            sys.exit(1)

        with open(mutant_path, "w", encoding="utf-8") as f:
            f.write(mutated_content)

        print(f"  -> Temporary mutant created at: {mutant_path}")
        print(f"  -> Modified line {diff_lines[0] + 1}:")
        print(f"     - Original: {orig_lines[diff_lines[0]]}")
        print(f"     + Mutated:  {mut_lines[diff_lines[0]]}")

        # Run the same regression test against mutant
        rc_mut, stdout_mut, stderr_mut = run_command(
            ["zsh", "-df", test_path, mutant_path], cwd=repo_root
        )

        mut_tests = parse_test_output(stdout_mut, stderr_mut)
        failed_mut = [t for t in mut_tests if t["status"] == "FAIL"]

        print("\n  --- Mutant Test Output ---")
        for line in stdout_mut.splitlines():
            print("  " + line)
        if stderr_mut.strip():
            for line in stderr_mut.splitlines():
                print("  [stderr] " + line)

        # Assertions on mutant rejection
        if rc_mut == 0:
            print("ERROR: Mutant unexpectedly passed the test suite! Regression test failed to protect condition.", file=sys.stderr)
            sys.exit(1)

        # Check intended assertion failure in T10
        regression_failed = any("T10_REGRESSION_path_inc_condition" in t["name"] for t in failed_mut)
        expected_failure_msg = "REGRESSION: _GCLOUD_PATH_INC_ACTIVE is not 1; path.zsh.inc was not sourced"
        assertion_found = expected_failure_msg in stdout_mut or expected_failure_msg in stderr_mut

        if not regression_failed or not assertion_found:
            print("ERROR: Mutant failed for an unintended reason (not the protected condition regression)!", file=sys.stderr)
            print(f"Failed tests: {failed_mut}", file=sys.stderr)
            sys.exit(1)

        print(f"\n  -> Mutant successfully REJECTED by regression assertion T10 as expected!")
        print(f"  -> Rejected by assertion: '{expected_failure_msg}'")

    finally:
        # Cleanup temporary mutant directory immediately
        shutil.rmtree(temp_dir, ignore_errors=True)
        print(f"  -> Temporary mutant directory cleaned up.")

    # Stage 5: Scenario C — Restore and retest original implementation
    print("\n[5/6] Scenario C: Verifying production source integrity and re-testing original")

    # Verify production source file is completely unmodified
    rc_git, out_git, _ = run_command(
        ["git", "status", "--porcelain", plugin_rel], cwd=repo_root
    )
    if out_git.strip():
        print(f"ERROR: Production file {plugin_rel} was modified or mutated!", file=sys.stderr)
        sys.exit(1)
    print(f"  -> Production source file {plugin_rel} is clean and untouched.")

    rc_retest, stdout_retest, stderr_retest = run_command(
        ["zsh", "-df", test_path], cwd=repo_root
    )
    retest_tests = parse_test_output(stdout_retest, stderr_retest)
    failed_retest = [t for t in retest_tests if t["status"] == "FAIL"]

    if rc_retest != 0 or failed_retest:
        print(f"ERROR: Post-cleanup retest failed!", file=sys.stderr)
        sys.exit(1)
    print(f"  -> Post-cleanup retest PASSED all {len(retest_tests)} tests.")

    # Stage 6: Generate evidence artifacts
    print("\n[6/6] Generating evidence artifacts in work/R14-T060/")

    results_data = {
        "task_id": "R14-T060",
        "plugin": "plugins/gcloud",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "tool_versions": tool_versions,
        "condition_details": condition_details,
        "scenario_a_original": {
            "exit_code": rc_orig,
            "total_tests": len(orig_tests),
            "passed_tests": len(orig_tests) - len(failed_orig),
            "failed_tests": len(failed_orig),
            "tests": orig_tests,
            "stdout": stdout_orig.strip(),
            "stderr": stderr_orig.strip(),
        },
        "scenario_b_mutant": {
            "exit_code": rc_mut,
            "total_tests": len(mut_tests),
            "passed_tests": len(mut_tests) - len(failed_mut),
            "failed_tests": len(failed_mut),
            "failed_test_names": [t["name"] for t in failed_mut],
            "rejected_by_intended_assertion": True,
            "rejection_message": expected_failure_msg,
            "infrastructure_failure": False,
            "stdout": stdout_mut.strip(),
            "stderr": stderr_mut.strip(),
        },
        "scenario_c_post_cleanup": {
            "exit_code": rc_retest,
            "total_tests": len(retest_tests),
            "passed_tests": len(retest_tests) - len(failed_retest),
            "failed_tests": len(failed_retest),
            "production_source_clean": True,
            "stdout": stdout_retest.strip(),
            "stderr": stderr_retest.strip(),
        },
        "verification_summary": {
            "original_passed": rc_orig == 0,
            "mutant_rejected": rc_mut != 0 and regression_failed,
            "post_cleanup_passed": rc_retest == 0,
            "production_intact": True,
            "zero_case_rejected": True,
        },
    }

    results_json_path = os.path.join(work_dir, "results.json")
    with open(results_json_path, "w", encoding="utf-8") as f:
        json.dump(results_data, f, indent=2)
    print(f"  -> Written {results_json_path}")

    report_txt_path = os.path.join(work_dir, "report.txt")
    with open(report_txt_path, "w", encoding="utf-8") as f:
        f.write("=================================================================\n")
        f.write(" R14-T060 Regression Mutation Verification Report: gcloud\n")
        f.write("=================================================================\n\n")
        f.write(f"Task ID: R14-T060\n")
        f.write(f"Plugin: {condition_details['source_file']}\n")
        f.write(f"Timestamp: {results_data['timestamp']}\n\n")

        f.write("Runtime Environment:\n")
        f.write(f"  Zsh: {tool_versions['zsh']}\n")
        f.write(f"  Python: {tool_versions['python']}\n")
        f.write(f"  Git Commit: {tool_versions['git_commit']}\n")
        f.write(f"  Git Branch: {tool_versions['git_branch']}\n\n")

        f.write("Protected Condition:\n")
        f.write(f"  Source File: {condition_details['source_file']}\n")
        f.write(f"  Line: {condition_details['line_number']}\n")
        f.write(f"  Original: {condition_details['original_condition']}\n")
        f.write(f"  Mutated:  {condition_details['mutated_condition']}\n")
        f.write(f"  Type:     {condition_details['mutation_type']}\n")
        f.write(f"  Purpose:  {condition_details['purpose']}\n\n")

        f.write("Scenario Execution Summary:\n")
        f.write(f"  Scenario A (Original Implementation):\n")
        f.write(f"    Exit Status: {rc_orig}\n")
        f.write(f"    Tests Run: {len(orig_tests)} (Passed: {len(orig_tests)}, Failed: 0)\n")
        f.write(f"    Outcome: PASS\n\n")

        f.write(f"  Scenario B (Temporary One-Condition Mutant):\n")
        f.write(f"    Exit Status: {rc_mut}\n")
        f.write(f"    Tests Run: {len(mut_tests)} (Passed: {len(mut_tests) - len(failed_mut)}, Failed: {len(failed_mut)})\n")
        f.write(f"    Mutant Rejection: CONFIRMED\n")
        f.write(f"    Intended Assertion: '{expected_failure_msg}'\n")
        f.write(f"    Infrastructure Failure: False\n")
        f.write(f"    Outcome: REJECTED AS EXPECTED\n\n")

        f.write(f"  Scenario C (Restore & Cleanup Retest):\n")
        f.write(f"    Production Source Clean: True\n")
        f.write(f"    Exit Status: {rc_retest}\n")
        f.write(f"    Tests Run: {len(retest_tests)} (Passed: {len(retest_tests)}, Failed: 0)\n")
        f.write(f"    Outcome: PASS\n\n")

        f.write("Tests Executed in Native Fixture Suite:\n")
        for t in orig_tests:
            f.write(f"  [{t['status']}] {t['name']}: {t['description']}\n")
        f.write("\nAll verification checks completed successfully.\n")

    print(f"  -> Written {report_txt_path}")
    print("\nAll checks completed successfully!")


if __name__ == "__main__":
    main()
