#!/usr/bin/env python3
"""
Automated check script for Oh My Zsh task R14-T059:
Integrate a focused check: history [plugins/history]
Issue: https://github.com/S-AI-Projects/ohmyzsh/issues/59
"""

import json
import os
import subprocess
import sys
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


def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    work_dir = os.path.join(repo_root, "work", "R14-T059")
    os.makedirs(work_dir, exist_ok=True)

    print("=================================================================")
    print(" Running R14-T059 Verification Harness: history focused checks  ")
    print("=================================================================")

    # Stage 1: Plugin syntax check
    plugin_path = "plugins/history/history.plugin.zsh"
    print(f"\n[1/4] Validating plugin syntax: zsh -n {plugin_path}")
    rc, out, err = run_command(["zsh", "-n", plugin_path], cwd=repo_root)
    if rc != 0:
        print(f"ERROR: Syntax check failed on {plugin_path}:\n{err}", file=sys.stderr)
        sys.exit(1)
    print("  -> Syntax check passed cleanly.")

    # Stage 2: Environment and tool version logging
    print("\n[2/4] Recording environment and runtime tool versions")
    tool_versions = get_tool_versions(repo_root)
    for k, v in tool_versions.items():
        print(f"  {k}: {v}")

    # Stage 3: Execute native test suite
    test_script = "plugins/history/tests/history.test.zsh"
    raw_records_file = os.path.join(work_dir, "raw_records.jsonl")
    if os.path.exists(raw_records_file):
        os.remove(raw_records_file)

    print(f"\n[3/4] Executing native test suite: zsh -df {test_script}")
    env = os.environ.copy()
    env["RECORD_JSON"] = raw_records_file
    env["PYTHON_BIN"] = sys.executable
    rc, out, err = run_command(["zsh", "-df", test_script], env=env, cwd=repo_root)

    print(out)
    if err:
        print(err, file=sys.stderr)

    if rc != 0:
        print(f"ERROR: Native test script failed with exit code {rc}", file=sys.stderr)
        sys.exit(rc)

    # Stage 4: Validate test records and generate evidence artifacts
    print("[4/4] Validating test results and generating evidence artifacts")
    if not os.path.exists(raw_records_file):
        print("ERROR: Native test suite did not produce raw_records.jsonl", file=sys.stderr)
        sys.exit(1)

    records = []
    with open(raw_records_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))

    # Reject zero-test execution
    if len(records) == 0:
        print("ERROR: Zero tests were executed! Failing as per requirement.", file=sys.stderr)
        sys.exit(1)

    passed_count = sum(1 for r in records if r.get("passed"))
    failed_count = len(records) - passed_count

    print(f"  -> Total tests executed: {len(records)}")
    print(f"  -> Passed: {passed_count}")
    print(f"  -> Failed: {failed_count}")

    if failed_count > 0:
        print("ERROR: One or more test assertions failed.", file=sys.stderr)
        sys.exit(1)

    # Ensure both success and failure/edge state assertions executed
    has_success = any(r.get("passed") and r.get("expected_status") == 0 for r in records)
    has_failure = any(r.get("passed") and r.get("expected_status") != 0 for r in records)

    if not has_success:
        print("ERROR: No successful execution assertions found in test run", file=sys.stderr)
        sys.exit(1)
    if not has_failure:
        print("ERROR: No failure assertions found in test run", file=sys.stderr)
        sys.exit(1)

    # Generate results.json
    results_data = {
        "task_id": "R14-T059",
        "item": "plugins/history",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "tool_versions": tool_versions,
        "summary": {
            "total": len(records),
            "passed": passed_count,
            "failed": failed_count,
            "has_success_assertion": has_success,
            "has_failure_assertion": has_failure,
        },
        "tests": records,
    }

    results_json_path = os.path.join(work_dir, "results.json")
    with open(results_json_path, "w", encoding="utf-8") as f:
        json.dump(results_data, f, indent=2)
    print(f"  -> Written {results_json_path}")

    # Generate report.txt
    report_txt_path = os.path.join(work_dir, "report.txt")
    with open(report_txt_path, "w", encoding="utf-8") as f:
        f.write("=================================================================\n")
        f.write(" Oh My Zsh - R14-T059 Verification Report: plugins/history\n")
        f.write("=================================================================\n\n")
        f.write(f"Timestamp:    {results_data['timestamp']}\n")
        f.write(f"Git Branch:   {tool_versions['git_branch']}\n")
        f.write(f"Git Commit:   {tool_versions['git_commit']}\n")
        f.write(f"Zsh Version:  {tool_versions['zsh']}\n")
        f.write(f"Python:       {tool_versions['python']}\n\n")
        f.write(f"Syntax Check: PASS (zsh -n {plugin_path})\n\n")
        f.write("Test Results Summary:\n")
        f.write(f"  - Total:   {len(records)}\n")
        f.write(f"  - Passed:  {passed_count}\n")
        f.write(f"  - Failed:  {failed_count}\n\n")
        f.write("Test Assertions Detail:\n")
        for r in records:
            status_str = "PASS" if r.get("passed") else "FAIL"
            f.write(f"  [{status_str}] {r['test_id']}: {r['description']}\n")
            f.write(f"         Mode: {r.get('mode')}\n")
            f.write(f"         Expected Status: {r.get('expected_status')} | Actual Status: {r.get('actual_status')}\n")
            if r.get("expected_command"):
                f.write(f"         Expected Command: {r.get('expected_command')} {r.get('expected_args')}\n")
                f.write(f"         Actual Command:   {r.get('actual_command')} {r.get('actual_args')}\n")
            if r.get("stdout"):
                f.write(f"         Stdout: {r.get('stdout')}\n")
            if r.get("stderr"):
                f.write(f"         Stderr: {r.get('stderr')}\n")
        f.write("\n=================================================================\n")
        f.write("All assertions passed. History plugin checks verified successfully.\n")
        f.write("=================================================================\n")
    print(f"  -> Written {report_txt_path}")

    # Clean up intermediate raw_records
    if os.path.exists(raw_records_file):
        os.remove(raw_records_file)

    print("\nAll checks completed successfully!")


if __name__ == "__main__":
    main()
