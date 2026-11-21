#!/usr/bin/env python3
"""
Automated check script for Oh My Zsh task R14-T053:
Verify state transitions: podman [plugins/podman]
Issue: https://github.com/S-AI-Projects/ohmyzsh/issues/53
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
    work_dir = os.path.join(repo_root, "work", "R14-T053")
    os.makedirs(work_dir, exist_ok=True)

    print("=================================================================")
    print(" Running R14-T053 Verification Harness: podman state transitions ")
    print("=================================================================")

    # Stage 1: Plugin syntax check
    plugin_path = "plugins/podman/podman.plugin.zsh"
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
    test_script = "plugins/podman/tests/podman.test.zsh"
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

    # Reject run if zero tests were recorded (Zero-test execution rejection)
    if not records:
        print("ERROR: Zero test records produced by test suite! Rejecting run.", file=sys.stderr)
        sys.exit(1)

    # Require both successful assertions and failure/edge-state assertions
    success_records = [r for r in records if r.get("expected", {}).get("status") == 0]
    failure_records = [r for r in records if r.get("expected", {}).get("status") != 0]

    if not success_records:
        print("ERROR: No successful test assertions found! Rejecting run.", file=sys.stderr)
        sys.exit(1)
    if not failure_records:
        print("ERROR: No failure/edge-state test assertions found! Rejecting run.", file=sys.stderr)
        sys.exit(1)

    # Validate state transition checks in all records
    for r in records:
        st = r.get("state_transitions", {})
        if not st.get("intended_change", {}).get("satisfied"):
            print(f"ERROR: Record {r.get('test_id')} failed intended state change!", file=sys.stderr)
            sys.exit(1)
        if not st.get("unrelated_state", {}).get("satisfied"):
            print(f"ERROR: Record {r.get('test_id')} failed unrelated state preservation!", file=sys.stderr)
            sys.exit(1)

    failures = [r for r in records if r.get("status") != "PASS"]
    passed_count = len(records) - len(failures)

    evidence = {
        "task_id": "R14-T053",
        "title": "Verify state transitions: podman",
        "repository": "S-AI-Projects/ohmyzsh",
        "issue": "https://github.com/S-AI-Projects/ohmyzsh/issues/53",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "tool_versions": tool_versions,
        "summary": {
            "total_tests": len(records),
            "passed": passed_count,
            "failed": len(failures),
            "success_cases": len(success_records),
            "failure_edge_cases": len(failure_records),
            "overall_status": "PASS" if not failures else "FAIL",
        },
        "tests": records,
    }

    # Save results.json
    results_json_path = os.path.join(work_dir, "results.json")
    with open(results_json_path, "w", encoding="utf-8") as f:
        json.dump(evidence, f, indent=2)

    # Save human-readable report.txt
    report_txt_path = os.path.join(work_dir, "report.txt")
    with open(report_txt_path, "w", encoding="utf-8") as f:
        f.write("=================================================================\n")
        f.write(" Task R14-T053: podman State Transitions Contract Verification\n")
        f.write("=================================================================\n\n")
        f.write(f"Timestamp: {evidence['timestamp']}\n")
        f.write(f"Git Commit: {tool_versions['git_commit']} ({tool_versions['git_branch']})\n")
        f.write(f"Zsh Version: {tool_versions['zsh']}\n")
        f.write(f"Python Version: {tool_versions['python']}\n\n")
        f.write(f"Summary: {passed_count}/{len(records)} passed ({len(failures)} failed)\n")
        f.write(f"         {len(success_records)} success cases, {len(failure_records)} failure/edge cases\n\n")
        f.write("Test Results Detail:\n")
        f.write("-----------------------------------------------------------------\n")
        for i, r in enumerate(records):
            status_tag = r["status"]
            f.write(f"[{status_tag}] {r['test_id']}: {r['description']}\n")
            f.write(f"       Mode: {r['mode']} | Alias: {r['alias']}\n")
            if r["expected"]["command"]:
                f.write(f"       Expected command: {r['expected']['command']} {r['expected']['args']}\n")
                f.write(f"       Actual command:   {r['actual']['command']} {r['actual']['args']}\n")
            f.write(f"       Expected status:  {r['expected']['status']} | Actual status: {r['actual']['status']}\n")
            st = r["state_transitions"]
            f.write(f"       Intended Change:  {st['intended_change']['detail']}\n")
            f.write(f"       Unrelated State:  {st['unrelated_state']['detail']}\n")
            if r["actual"].get("stderr"):
                f.write(f"       Actual stderr:    {r['actual']['stderr'].strip()}\n")
            if r.get("errors"):
                f.write(f"       Errors: {r['errors']}\n")
            if i < len(records) - 1:
                f.write("\n")

    if os.path.exists(raw_records_file):
        os.remove(raw_records_file)

    print("=================================================================")
    print(f" Evidence saved to:\n  - {results_json_path}\n  - {report_txt_path}")
    print(f" Summary: {passed_count}/{len(records)} passed, {len(failures)} failed.")
    print("=================================================================")

    if failures:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
