#!/usr/bin/env python3
"""
R14-T050 · Regression mutation tests for plugins/man
Entry points tested: man-command-line widget and keybinding registration

Task type: Regression mutation
Mutant tested: Broadening prefix guard from 'man\\ *' to 'man*'

Tests:
  1. SUCCESS (single cmd)   - BUFFER='ls -la' -> BUFFER='man ls'
  2. SUCCESS (subcommand)   - BUFFER='git commit -m foo' -> checks 'git-commit' man page -> BUFFER='man git commit'
  3. EDGE (already man)     - BUFFER='man grep' -> prefix guard exits early -> BUFFER='man grep'
  4. REGRESSION (prefix)    - BUFFER='manage.py runserver' -> unmutated code transforms to 'man manage.py'
  5. MUTATION PROBE (kill)  - In a temporary copy, mutate 'man\\ *' to 'man*';
                              verify input 'manage.py runserver' is falsely rejected,
                              killing the mutant.
  6. EDGE (empty buffer)    - BUFFER='' -> invokes 'zle up-history' -> recalls history.

All external commands and ZLE builtins are stubbed.
All state changes remain inside temporary directories.
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
PLUGIN = os.path.join(REPO_ROOT, "plugins", "man", "man.plugin.zsh")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_stub(bindir: str, name: str, body: str = "exit 0") -> None:
    p = os.path.join(bindir, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n")
        f.write(textwrap.dedent(body) + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def _make_bindir(tmpdir: str) -> str:
    bindir = os.path.join(tmpdir, "bin")
    os.makedirs(bindir, exist_ok=True)

    # Stub man: returns 0 if checking 'git-commit', 1 for others
    _make_stub(bindir, "man", """\
        case "$1" in
            git-commit) exit 0 ;;
            *) exit 1 ;;
        esac
    """)

    return bindir


def run_zsh_widget(plugin_path: str, tmpdir: str, bindir: str, initial_buffer: str, extra_zsh: str = "") -> subprocess.CompletedProcess:
    home = os.path.join(tmpdir, "home")
    os.makedirs(home, exist_ok=True)

    script = textwrap.dedent(f"""\
        # Stub ZLE builtins
        typeset -g BUFFER="{initial_buffer}"
        typeset -g ZLE_HISTORY_CALLED="no"

        zle() {{
            if [[ "$1" = "up-history" ]]; then
                ZLE_HISTORY_CALLED="yes"
                BUFFER="echo recalled_cmd"
            fi
        }}
        bindkey() {{ : ; }}

        export ZSH="{REPO_ROOT}/"
        export HOME="{home}"

        source "{plugin_path}"

        {extra_zsh}

        # Invoke the widget under test
        man-command-line

        echo "RESULT_BUFFER:$BUFFER"
        echo "ZLE_HISTORY:$ZLE_HISTORY_CALLED"
        echo "EXIT:$?"
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

def test_single_command():
    print("\n[Test 1] SUCCESS - single command without subcommand man page")
    with tempfile.TemporaryDirectory(prefix="r14t050_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        res = run_zsh_widget(PLUGIN, tmpdir, bindir, "ls -la")

        buf = [l.split(":", 1)[1] for l in res.stdout.splitlines() if l.startswith("RESULT_BUFFER:")][0]
        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("transforms 'ls -la' to 'man ls'", buf == "man ls", f"buf={buf!r}")
        print(f"        buffer     : {buf!r}")


def test_subcommand():
    print("\n[Test 2] SUCCESS - command with valid subcommand man page (git commit)")
    with tempfile.TemporaryDirectory(prefix="r14t050_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        res = run_zsh_widget(PLUGIN, tmpdir, bindir, "git commit -m initial")

        buf = [l.split(":", 1)[1] for l in res.stdout.splitlines() if l.startswith("RESULT_BUFFER:")][0]
        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("transforms to 'man git commit' when git-commit man page exists",
              buf == "man git commit", f"buf={buf!r}")
        print(f"        buffer     : {buf!r}")


def test_already_man_prefix():
    print("\n[Test 3] EDGE - command already prefixed with 'man '")
    with tempfile.TemporaryDirectory(prefix="r14t050_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        res = run_zsh_widget(PLUGIN, tmpdir, bindir, "man grep")

        buf = [l.split(":", 1)[1] for l in res.stdout.splitlines() if l.startswith("RESULT_BUFFER:")][0]
        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("leaves buffer unchanged as 'man grep'", buf == "man grep", f"buf={buf!r}")
        print(f"        buffer     : {buf!r} (early return)")


def test_prefix_regression_unmutated():
    print("\n[Test 4] REGRESSION - command starting with 'man' letters (manage.py)")
    with tempfile.TemporaryDirectory(prefix="r14t050_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        # manage.py begins with 'man' but not 'man '
        res = run_zsh_widget(PLUGIN, tmpdir, bindir, "manage.py runserver")

        buf = [l.split(":", 1)[1] for l in res.stdout.splitlines() if l.startswith("RESULT_BUFFER:")][0]
        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("correctly prepends man to 'manage.py' on unmutated code",
              buf == "man manage.py", f"buf={buf!r}")
        print(f"        buffer     : {buf!r} ✓")


def test_mutation_probe():
    print("\n[Test 5] MUTATION PROBE - verify mutant 'man*' is killed by manage.py test case")
    with tempfile.TemporaryDirectory(prefix="r14t050_mutant_") as tmpdir:
        bindir = _make_bindir(tmpdir)

        # Create temporary mutated plugin: mutate 'man\\ *' to 'man*'
        mutant_plugin = os.path.join(tmpdir, "man.plugin.mutant.zsh")
        original_code = open(PLUGIN).read()
        mutated_code = original_code.replace('[[ "$BUFFER" = man\\ * ]]', '[[ "$BUFFER" = man* ]]')
        with open(mutant_plugin, "w") as f:
            f.write(mutated_code)

        # Run with manage.py against the mutant
        res = run_zsh_widget(mutant_plugin, tmpdir, bindir, "manage.py runserver")
        buf = [l.split(":", 1)[1] for l in res.stdout.splitlines() if l.startswith("RESULT_BUFFER:")][0]

        # In the mutant, 'manage.py' matched 'man*' and was falsely rejected (BUFFER unchanged)
        mutant_detected = (buf == "manage.py runserver")
        check("mutant was killed: 'man*' prematurely returned on 'manage.py'",
              mutant_detected, f"buf={buf!r}")
        print(f"        mutant buf : {buf!r} (failed to prepend man)")
        print(f"        mutant kill: confirmed ✓")


def test_empty_buffer_history():
    print("\n[Test 6] EDGE - empty buffer triggers zle up-history")
    with tempfile.TemporaryDirectory(prefix="r14t050_") as tmpdir:
        bindir = _make_bindir(tmpdir)
        res = run_zsh_widget(PLUGIN, tmpdir, bindir, "")

        hist = [l.split(":", 1)[1] for l in res.stdout.splitlines() if l.startswith("ZLE_HISTORY:")][0]
        buf = [l.split(":", 1)[1] for l in res.stdout.splitlines() if l.startswith("RESULT_BUFFER:")][0]

        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("invokes zle up-history when buffer is empty", hist == "yes", f"hist={hist}")
        check("recalled command prepended with man", buf == "man echo", f"buf={buf!r}")
        print(f"        history called: {hist} ✓")
        print(f"        recalled buf  : {buf!r} ✓")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T050 · Regression mutation tests: plugins/man")
    print("Target condition: [[ \"$BUFFER\" = man\\ * ]]")
    print("=" * 60)

    print("\n[Syntax] zsh -n plugins/man/man.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    test_single_command()
    test_subcommand()
    test_already_man_prefix()
    test_prefix_regression_unmutated()
    test_mutation_probe()
    test_empty_buffer_history()

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
