#!/usr/bin/env python3
"""
R14-T042 · Argument-boundary tests for plugins/aws/aws.plugin.zsh
Entry points tested: agp, agr, _aws_update_state

Tests:
  1. SUCCESS  — agp with AWS_PROFILE set prints the profile name; exit 0.
  2. SUCCESS  — agr with AWS_REGION set prints the region name; exit 0.
  3. EDGE     — agp with AWS_PROFILE unset prints an empty line; exit 0.
                (Minimum accepted argument list: no arguments required.)
  4. EDGE     — agr with AWS_REGION unset prints empty; exit 0.
  5. BOUNDARY — _aws_update_state with state enabled but missing parent
                directory returns exit status 1 (documented failure path).
  6. BOUNDARY — _aws_update_state with state disabled is a no-op; exit 0.

All external commands (aws, aws_completer, compctl, compinit, autoload, …)
are stubbed via a temporary PATH. No real AWS credentials or services needed.
No user/global configuration is modified.
"""

import os
import stat
import subprocess
import sys
import tempfile
import textwrap

REPO_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
)
PLUGIN = os.path.join(REPO_ROOT, "plugins", "aws", "aws.plugin.zsh")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_stub(bindir: str, name: str, body: str = 'exit 0') -> None:
    p = os.path.join(bindir, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n")
        f.write(textwrap.dedent(body) + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def _make_bindir(tmpdir: str) -> str:
    bindir = os.path.join(tmpdir, "bin")
    os.makedirs(bindir, exist_ok=True)
    for name in ["aws", "aws_completer", "brew", "compctl", "compinit",
                 "bashcompinit", "autoload", "complete"]:
        _make_stub(bindir, name)
    return bindir


def run_zsh(tmpdir: str, bindir: str, env_vars: dict, body: str) -> subprocess.CompletedProcess:
    """Run body in a minimal no-rc zsh session that sources the plugin.

    env_vars: dict of env variables to export INSIDE the zsh script (after
    sourcing the plugin), so they are not clobbered by the plugin's own
    state-restore logic at source time.
    """
    home = os.path.join(tmpdir, "home")
    os.makedirs(home, exist_ok=True)

    # Build export lines to inject after the plugin is sourced
    export_lines = "\n".join(
        f'export {k}="{v}"' for k, v in env_vars.items()
    )

    script = textwrap.dedent(f"""\
        # Zsh stubs for builtins used by the plugin at sourcing time
        function autoload {{ : ; }}
        function compctl  {{ : ; }}
        function bashcompinit {{ : ; }}
        function complete {{ : ; }}
        function compinit  {{ : ; }}
        function aws_completer {{ : ; }}
        # Minimal colour/reset stubs
        typeset -A fg; fg[red]=""
        reset_color=""

        export ZSH="{REPO_ROOT}/"
        export HOME="{home}"
        export AWS_CONFIG_FILE="{home}/.aws/config"
        export SHOW_AWS_PROMPT=false
        export AWS_PROFILE_STATE_ENABLED=false

        source "{PLUGIN}"

        # Set test-specific env vars AFTER sourcing so the plugin's
        # state-restore block cannot overwrite them
        {export_lines}

        {body}
    """)
    script_path = os.path.join(tmpdir, "script.zsh")
    with open(script_path, "w") as f:
        f.write(script)

    env = os.environ.copy()
    env["PATH"] = bindir + ":" + env.get("PATH", "")
    env["HOME"] = home
    env["SHOW_AWS_PROMPT"] = "false"
    # Strip inherited AWS vars — the script sets them explicitly after sourcing
    for k in ["AWS_PROFILE", "AWS_DEFAULT_PROFILE", "AWS_REGION",
              "AWS_DEFAULT_REGION", "AWS_PROFILE_STATE_ENABLED"]:
        env.pop(k, None)

    return subprocess.run(
        ["zsh", "--no-rcs", "--no-globalrcs", script_path],
        capture_output=True, text=True, env=env,
    )


# ---------------------------------------------------------------------------
# Check harness
# ---------------------------------------------------------------------------

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"
failures: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  {PASS}  {label}")
    else:
        failures.append(label)
        msg = f"  {FAIL}  {label}"
        if detail:
            msg += f"\n        detail: {detail}"
        print(msg)


# ---------------------------------------------------------------------------
# Test 1 — agp: profile set → prints profile name, exit 0
# ---------------------------------------------------------------------------

def test_agp_with_profile():
    print("\n[Test 1] agp — AWS_PROFILE set → prints profile name; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t042_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        result = run_zsh(tmpdir, bindir,
                         {"AWS_PROFILE": "my-dev-profile"},
                         "export AWS_PROFILE=my-dev-profile\nagp")
        actual = result.stdout.strip()
        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("output is profile name 'my-dev-profile'", actual == "my-dev-profile",
              f"actual={actual!r}")
        print(f"        args       : AWS_PROFILE=my-dev-profile  (no positional args)")
        print(f"        output     : {actual!r}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 2 — agr: region set → prints region, exit 0
# ---------------------------------------------------------------------------

def test_agr_with_region():
    print("\n[Test 2] agr — AWS_REGION set → prints region; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t042_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        result = run_zsh(tmpdir, bindir,
                         {"AWS_REGION": "us-east-1"},
                         "agr")
        actual = result.stdout.strip()
        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("output is region 'us-east-1'", actual == "us-east-1",
              f"actual={actual!r}")
        print(f"        args       : AWS_REGION=us-east-1  (no positional args)")
        print(f"        output     : {actual!r}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 3 — agp EDGE: no AWS_PROFILE → empty output, exit 0
# ---------------------------------------------------------------------------

def test_agp_no_profile():
    print("\n[Test 3] agp EDGE — AWS_PROFILE unset → empty output; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t042_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        result = run_zsh(tmpdir, bindir, {}, "agp")
        actual = result.stdout.strip()
        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("output is empty (no profile set)", actual == "",
              f"actual={actual!r}")
        print(f"        args       : (AWS_PROFILE unset, no positional args)")
        print(f"        output     : {actual!r}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 4 — agr EDGE: no AWS_REGION → empty output, exit 0
# ---------------------------------------------------------------------------

def test_agr_no_region():
    print("\n[Test 4] agr EDGE — AWS_REGION unset → empty output; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t042_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        result = run_zsh(tmpdir, bindir, {}, "agr")
        actual = result.stdout.strip()
        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("output is empty (no region set)", actual == "",
              f"actual={actual!r}")
        print(f"        args       : (AWS_REGION unset, no positional args)")
        print(f"        output     : {actual!r}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 5 — _aws_update_state BOUNDARY: state enabled, missing dir → exit 1
# ---------------------------------------------------------------------------

def test_update_state_missing_dir():
    print("\n[Test 5] _aws_update_state BOUNDARY — state enabled, missing dir → exit 1")
    with tempfile.TemporaryDirectory(prefix="r14t042_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        # Point state file to a path whose parent directory does NOT exist
        bad_state = os.path.join(tmpdir, "nonexistent_dir", "state_file")
        body = textwrap.dedent(f"""\
            export AWS_PROFILE_STATE_ENABLED=true
            export AWS_STATE_FILE="{bad_state}"
            export AWS_PROFILE="boundary-profile"
            export AWS_REGION="eu-west-1"
            _aws_update_state
            echo "exit_status:$?"
        """)
        result = run_zsh(tmpdir, bindir, {}, body)
        output = result.stdout.strip()
        # Extract exit status reported by the shell
        exit_status_line = [l for l in output.splitlines() if l.startswith("exit_status:")]
        inner_rc = int(exit_status_line[0].split(":")[1]) if exit_status_line else -1
        check("_aws_update_state returns exit 1 when parent dir missing",
              inner_rc == 1,
              f"inner_rc={inner_rc}  full_output={output!r}")
        check("state file was NOT created (dir missing)", not os.path.exists(bad_state),
              f"file unexpectedly exists: {bad_state}")
        print(f"        AWS_STATE_FILE : {bad_state}")
        print(f"        inner exit     : {inner_rc}")
        print(f"        file exists    : {os.path.exists(bad_state)}")


# ---------------------------------------------------------------------------
# Test 6 — _aws_update_state BOUNDARY: state disabled → no-op, exit 0
# ---------------------------------------------------------------------------

def test_update_state_disabled():
    print("\n[Test 6] _aws_update_state BOUNDARY — state disabled → no-op; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t042_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        state_file = os.path.join(tmpdir, "state_file")
        body = textwrap.dedent(f"""\
            export AWS_PROFILE_STATE_ENABLED=false
            export AWS_STATE_FILE="{state_file}"
            export AWS_PROFILE="some-profile"
            export AWS_REGION="ap-south-1"
            _aws_update_state
            echo "exit_status:$?"
        """)
        result = run_zsh(tmpdir, bindir, {}, body)
        output = result.stdout.strip()
        exit_status_line = [l for l in output.splitlines() if l.startswith("exit_status:")]
        inner_rc = int(exit_status_line[0].split(":")[1]) if exit_status_line else -1
        check("_aws_update_state exit 0 when disabled", inner_rc == 0,
              f"inner_rc={inner_rc}  full_output={output!r}")
        check("state file not written when disabled", not os.path.exists(state_file),
              f"file unexpectedly written: {state_file}")
        print(f"        AWS_PROFILE_STATE_ENABLED : false")
        print(f"        inner exit                : {inner_rc}")
        print(f"        file created              : {os.path.exists(state_file)}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T042 · Argument-boundary tests: plugins/aws")
    print("Entry points: agp, agr, _aws_update_state")
    print("=" * 60)

    print("\n[Syntax] zsh -n plugins/aws/aws.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    test_agp_with_profile()
    test_agr_with_region()
    test_agp_no_profile()
    test_agr_no_region()
    test_update_state_missing_dir()
    test_update_state_disabled()

    print("\n" + "=" * 60)
    if failures:
        print(f"RESULT: {len(failures)} check(s) FAILED:")
        for f in failures:
            print(f"  - {f}")
        print("=" * 60)
        sys.exit(1)
    else:
        print("RESULT: All checks PASSED")
        print("=" * 60)
        sys.exit(0)


if __name__ == "__main__":
    main()
