#!/usr/bin/env python3
"""
R14-T048 · Failure diagnostics and troubleshooting tests for plugins/rails
Entry points tested:
  - devlog -> tail -f log/development.log
  - rails  -> _rails_command
  - rake   -> _rake_command

Task type: Failure diagnostics
Tests:
  1. FAILURE (devlog)   - Fails when log/development.log is missing, exits non-zero (1).
  2. SUCCESS (devlog)   - After correcting fixture (creating log/development.log), succeeds (exit 0).
  3. SUCCESS (rails)    - _rails_command invokes bin/rails when present (exit 0).
  4. SUCCESS (rails-fb) - _rails_command falls back to command rails when bin/rails is absent (exit 0).
  5. SUCCESS (rake)     - _rake_command invokes bundle exec rake when Gemfile is present (exit 0).

All external commands (tail, rails, rake, bundle, ruby) are stubbed.
All state changes remain inside isolated temporary directories.
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
PLUGIN = os.path.join(REPO_ROOT, "plugins", "rails", "rails.plugin.zsh")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_stub(bindir: str, name: str, body: str = "exit 0") -> None:
    p = os.path.join(bindir, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n")
        f.write(textwrap.dedent(body) + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def _make_bindir(tmpdir: str, argv_log: str) -> str:
    bindir = os.path.join(tmpdir, "bin")
    os.makedirs(bindir, exist_ok=True)

    # Stub tail: logs argv; checks if target file exists. If not, returns 1.
    _make_stub(bindir, "tail", f"""\
        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done
        # The last argument is typically the file to tail
        target=""
        for last in "$@"; do target="$last"; done
        if [ ! -f "$target" ]; then
            echo "tail: $target: No such file or directory" >&2
            exit 1
        fi
        echo "Tailing $target"
        exit 0
    """)

    # Stub system rails
    _make_stub(bindir, "rails", f"""\
        printf 'system-rails\\n' >> "{argv_log}"
        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done
        exit 0
    """)

    # Stub system rake
    _make_stub(bindir, "rake", f"""\
        printf 'system-rake\\n' >> "{argv_log}"
        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done
        exit 0
    """)

    # Stub bundle
    _make_stub(bindir, "bundle", f"""\
        printf 'bundle\\n' >> "{argv_log}"
        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done
        exit 0
    """)

    return bindir


def run_zsh(tmpdir: str, bindir: str, workdir: str, body: str) -> subprocess.CompletedProcess:
    home = os.path.join(tmpdir, "home")
    os.makedirs(home, exist_ok=True)
    os.makedirs(workdir, exist_ok=True)

    script = textwrap.dedent(f"""\
        function compdef {{ : ; }}

        export ZSH="{REPO_ROOT}/"
        export HOME="{home}"
        cd "{workdir}"

        source "{PLUGIN}"

        {body}
    """)
    script_path = os.path.join(home, "script.zsh")
    with open(script_path, "w") as f:
        f.write(script)

    env = os.environ.copy()
    env["PATH"] = bindir + ":" + env.get("PATH", "")
    env["HOME"] = home

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
        print(f"  {FAIL}  {label}" + (f"\n        detail: {detail}" if detail else ""))


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_devlog_failure_and_recovery():
    print("\n[Test 1 & 2] FAILURE & RECOVERY - devlog missing log file, then corrected")
    with tempfile.TemporaryDirectory(prefix="r14t048_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)
        workdir = os.path.join(tmpdir, "workdir")

        # Step 1: Execute devlog when log/development.log does NOT exist
        body_fail = textwrap.dedent("""\
            devlog
            echo "FAIL_STATUS:$?"
        """)
        res_fail = run_zsh(tmpdir, bindir, workdir, body_fail)

        check("missing log file produces non-zero exit status (1)",
              "FAIL_STATUS:1" in res_fail.stdout or res_fail.returncode == 1,
              f"out={res_fail.stdout} err={res_fail.stderr}")
        check("stderr produces diagnostic message 'No such file or directory'",
              "No such file or directory" in res_fail.stderr,
              f"err={res_fail.stderr}")
        print(f"        failure verified: {res_fail.stderr.strip()}")

        # Step 2: Apply diagnostic correction: create log/development.log
        os.makedirs(os.path.join(workdir, "log"), exist_ok=True)
        with open(os.path.join(workdir, "log", "development.log"), "w") as f:
            f.write("Rails server boot logs...\n")

        # Clear argv log
        if os.path.exists(argv_log):
            os.remove(argv_log)

        # Step 3: Re-execute devlog in corrected environment
        body_success = textwrap.dedent("""\
            devlog
            echo "SUCCESS_STATUS:$?"
        """)
        res_success = run_zsh(tmpdir, bindir, workdir, body_success)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("corrected invocation succeeds with exit status 0",
              "SUCCESS_STATUS:0" in res_success.stdout,
              f"out={res_success.stdout}")
        check("tail received expected arguments ['-f', 'log/development.log']",
              args == ["-f", "log/development.log"],
              f"args={args}")
        print(f"        recovery verified: tail succeeded on log/development.log ✓")


def test_rails_binstub_dispatch():
    print("\n[Test 3] SUCCESS - _rails_command uses bin/rails when present")
    with tempfile.TemporaryDirectory(prefix="r14t048_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)
        workdir = os.path.join(tmpdir, "workdir")
        os.makedirs(os.path.join(workdir, "bin"), exist_ok=True)

        # Create local binstub
        local_binstub = os.path.join(workdir, "bin", "rails")
        with open(local_binstub, "w") as f:
            f.write(f"#!/bin/sh\necho local-binstub >> '{argv_log}'\nexit 0\n")
        os.chmod(local_binstub, 0o755)

        body = textwrap.dedent("""\
            rails s -p 3000
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, workdir, body)
        calls = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("dispatches to local bin/rails binstub", "local-binstub" in calls,
              f"calls={calls}")
        print(f"        binstub dispatch: local bin/rails executed ✓")


def test_rails_fallback_dispatch():
    print("\n[Test 4] SUCCESS - _rails_command falls back to system rails when no binstub")
    with tempfile.TemporaryDirectory(prefix="r14t048_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)
        workdir = os.path.join(tmpdir, "workdir")

        body = textwrap.dedent("""\
            rails new myapp
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, workdir, body)
        calls = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("falls back to system rails command", "system-rails" in calls,
              f"calls={calls}")
        print(f"        fallback dispatch: system rails executed ✓")


def test_rake_bundle_exec_dispatch():
    print("\n[Test 5] SUCCESS - _rake_command wraps with bundle exec when Gemfile present")
    with tempfile.TemporaryDirectory(prefix="r14t048_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)
        workdir = os.path.join(tmpdir, "workdir")
        os.makedirs(workdir, exist_ok=True)
        # Touch Gemfile to simulate bundler Rails project
        with open(os.path.join(workdir, "Gemfile"), "w") as f:
            f.write("source 'https://rubygems.org'\n")

        body = textwrap.dedent("""\
            rake db:migrate
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, workdir, body)
        calls = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("bundle wrapper invoked", "bundle" in calls, f"calls={calls}")
        check("arguments match bundle exec rake db:migrate",
              "exec" in calls and "rake" in calls and "db:migrate" in calls,
              f"calls={calls}")
        print(f"        bundle exec dispatch: bundle exec rake db:migrate ✓")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T048 · Failure diagnostics tests: plugins/rails")
    print("Entry points: devlog, rails, rake")
    print("=" * 60)

    print("\n[Syntax] zsh -n plugins/rails/rails.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    test_devlog_failure_and_recovery()
    test_rails_binstub_dispatch()
    test_rails_fallback_dispatch()
    test_rake_bundle_exec_dispatch()

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
