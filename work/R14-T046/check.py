#!/usr/bin/env python3
"""
R14-T046 · Characterization and implementation readability tests for plugins/npm
Entry points tested:
  - npmg -> npm i -g 
  - npmS -> npm i -S 
  - npmD -> npm i -D 

Tests:
  1. SUCCESS (npmg)  - Characterize npmg alias: expands to 'npm i -g ' and forwards
                       arguments to npm with exit status 0.
  2. SUCCESS (npmS)  - Characterize npmS alias: expands to 'npm i -S ' and forwards
                       arguments to npm with exit status 0.
  3. SUCCESS (npmD)  - Characterize npmD alias: expands to 'npm i -D ' and forwards
                       arguments to npm with exit status 0.
  4. EDGE (chaining) - Characterize trailing space: alias expansion preserves multiple
                       arguments in exact order.
  5. EDGE (missing)  - When npm command is absent during sourcing, the completion
                       registration is skipped, but aliases remain defined.
  6. FAILURE (status)- When npm fails (exit code 1), the non-zero status propagates
                       cleanly through the alias.

All external commands are stubbed on a temporary PATH.
No real npm service or package manager is invoked.
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
PLUGIN = os.path.join(REPO_ROOT, "plugins", "npm", "npm.plugin.zsh")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_stub(bindir: str, name: str, body: str = "exit 0") -> None:
    p = os.path.join(bindir, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n")
        f.write(textwrap.dedent(body) + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def _make_bindir(tmpdir: str, argv_log: str, exit_code: int = 0) -> str:
    bindir = os.path.join(tmpdir, "bin")
    os.makedirs(bindir, exist_ok=True)
    _make_stub(bindir, "npm", f"""\
        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done
        exit {exit_code}
    """)
    return bindir


def run_zsh(tmpdir: str, bindir: str, body: str, include_stubs: bool = True) -> subprocess.CompletedProcess:
    home = os.path.join(tmpdir, "home")
    cache = os.path.join(tmpdir, "cache")
    os.makedirs(home, exist_ok=True)
    os.makedirs(cache, exist_ok=True)

    script = textwrap.dedent(f"""\
        # Stub Zsh builtins/modules needed for compdef and zle
        function compdef {{ : ; }}
        function compadd {{ : ; }}
        function zle     {{ : ; }}
        function bindkey {{ : ; }}

        export ZSH="{REPO_ROOT}/"
        export HOME="{home}"
        export ZSH_CACHE_DIR="{cache}"

        source "{PLUGIN}"

        {body}
    """)
    script_path = os.path.join(home, "script.zsh")
    with open(script_path, "w") as f:
        f.write(script)

    env = os.environ.copy()
    if include_stubs:
        env["PATH"] = bindir + ":" + env.get("PATH", "")
    else:
        # Isolated PATH with no npm
        env["PATH"] = "/usr/bin:/bin"
    env["HOME"] = home
    env["ZSH_CACHE_DIR"] = cache

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

def test_npmg():
    print("\n[Test 1] SUCCESS - npmg expands to 'npm i -g '")
    with tempfile.TemporaryDirectory(prefix="r14t046_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            # Characterize alias expansion
            alias_val=$(alias npmg 2>/dev/null)
            echo "ALIAS:$alias_val"
            npmg typescript
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", res.returncode == 0, f"rc={res.returncode} stderr={res.stderr}")
        check("alias npmg expands to 'npm i -g '", "npm i -g" in res.stdout, f"out={res.stdout}")
        check("arguments received by npm match ['i', '-g', 'typescript']",
              args == ["i", "-g", "typescript"], f"args={args}")
        print(f"        npm argv   : {args}")
        print(f"        exit status: {res.returncode}")


def test_npmS():
    print("\n[Test 2] SUCCESS - npmS expands to 'npm i -S '")
    with tempfile.TemporaryDirectory(prefix="r14t046_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            alias_val=$(alias npmS 2>/dev/null)
            echo "ALIAS:$alias_val"
            npmS express
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", res.returncode == 0, f"rc={res.returncode} stderr={res.stderr}")
        check("alias npmS expands to 'npm i -S '", "npm i -S" in res.stdout, f"out={res.stdout}")
        check("arguments received by npm match ['i', '-S', 'express']",
              args == ["i", "-S", "express"], f"args={args}")
        print(f"        npm argv   : {args}")
        print(f"        exit status: {res.returncode}")


def test_npmD():
    print("\n[Test 3] SUCCESS - npmD expands to 'npm i -D '")
    with tempfile.TemporaryDirectory(prefix="r14t046_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            alias_val=$(alias npmD 2>/dev/null)
            echo "ALIAS:$alias_val"
            npmD jest
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", res.returncode == 0, f"rc={res.returncode} stderr={res.stderr}")
        check("alias npmD expands to 'npm i -D '", "npm i -D" in res.stdout, f"out={res.stdout}")
        check("arguments received by npm match ['i', '-D', 'jest']",
              args == ["i", "-D", "jest"], f"args={args}")
        print(f"        npm argv   : {args}")
        print(f"        exit status: {res.returncode}")


def test_trailing_space_multiargs():
    print("\n[Test 4] EDGE - multi-package argument preservation with trailing space")
    with tempfile.TemporaryDirectory(prefix="r14t046_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            npmD eslint prettier @types/node
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", res.returncode == 0, f"rc={res.returncode}")
        check("all package names forwarded in order",
              args == ["i", "-D", "eslint", "prettier", "@types/node"],
              f"args={args}")
        print(f"        npm argv   : {args}")


def test_missing_npm_dependency():
    print("\n[Test 5] EDGE - missing npm dependency branch")
    with tempfile.TemporaryDirectory(prefix="r14t046_") as tmpdir:
        bindir = os.path.join(tmpdir, "bin")
        os.makedirs(bindir, exist_ok=True)
        # Empty bin with no npm stub

        body = textwrap.dedent("""\
            # Verify aliases are still defined even when npm is absent
            if alias npmg >/dev/null 2>&1 && alias npmS >/dev/null 2>&1 && alias npmD >/dev/null 2>&1; then
                echo "ALIASES:defined"
            else
                echo "ALIASES:missing"
            fi

            # Verify completion function is not registered
            if typeset -f _npm_completion >/dev/null 2>&1; then
                echo "COMPLETION:defined"
            else
                echo "COMPLETION:absent"
            fi
        """)
        res = run_zsh(tmpdir, bindir, body, include_stubs=False)

        check("exit status 0 when npm absent", res.returncode == 0, f"rc={res.returncode}")
        check("aliases npmg, npmS, npmD are still defined", "ALIASES:defined" in res.stdout,
              f"out={res.stdout}")
        check("_npm_completion is not registered when npm is absent",
              "COMPLETION:absent" in res.stdout, f"out={res.stdout}")
        print(f"        aliases    : defined ✓")
        print(f"        completion : absent (skipped guard branch) ✓")


def test_failure_propagation():
    print("\n[Test 6] FAILURE - non-zero exit status propagates from npm")
    with tempfile.TemporaryDirectory(prefix="r14t046_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        # Stub npm that exits with code 1
        bindir = _make_bindir(tmpdir, argv_log, exit_code=1)

        body = textwrap.dedent("""\
            npmg invalid-package-nonexistent
            echo "EXIT_CODE:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        out_lines = [l for l in res.stdout.splitlines() if l.startswith("EXIT_CODE:")]
        ec = out_lines[0].split(":")[1] if out_lines else "0"

        check("exit status propagates non-zero (code 1)", ec == "1", f"ec={ec}")
        print(f"        reported exit: {ec}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T046 · Characterization tests: plugins/npm")
    print("Entry points: npmg, npmS, npmD")
    print("=" * 60)

    print("\n[Syntax] zsh -n plugins/npm/npm.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    test_npmg()
    test_npmS()
    test_npmD()
    test_trailing_space_multiargs()
    test_missing_npm_dependency()
    test_failure_propagation()

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
