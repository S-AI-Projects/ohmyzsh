#!/usr/bin/env python3
"""
R14-T045 · Environment-isolation tests for plugins/deno/deno.plugin.zsh
Entry points tested: dc (deno compile), dca (deno cache), dck (deno check)

Task type: Environment isolation

Tests:
  1. SUCCESS  — dc passes args as: deno compile <file>; exit 0.
                Uses a temporary working directory and local stub config.
  2. SUCCESS  — dca passes args as: deno cache <file>; exit 0.
  3. SUCCESS  — dck passes args as: deno check <file>; exit 0.
  4. MISSING-DEP — when 'deno' is absent from PATH, the plugin returns early
                   (aliases dc/dca/dck are still defined — they're declared
                   before the guard) but the completion block is skipped.
  5. ISOLATION — DENO_DIR and DENO_INSTALL_ROOT env vars from the outer shell
                 do not leak into the test; each test uses its own tmpdir.

All external commands are replaced by stubs on a temporary PATH.
No real Deno installation, network, or user configuration is modified.
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
PLUGIN = os.path.join(REPO_ROOT, "plugins", "deno", "deno.plugin.zsh")

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
    # deno stub: skip 'completions' call, log everything else
    _make_stub(bindir, "deno", f"""\
        if [ "$1" = "completions" ]; then exit 0; fi
        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done
        exit 0
    """)
    _make_stub(bindir, "zf_mv", 'cp "$3" "$4" 2>/dev/null; exit 0')
    return bindir


def run_zsh(tmpdir: str, bindir: str, body: str, extra_env: dict = None) -> subprocess.CompletedProcess:
    home = os.path.join(tmpdir, "home")
    cache = os.path.join(tmpdir, "cache")
    workdir = os.path.join(tmpdir, "workdir")
    os.makedirs(home, exist_ok=True)
    os.makedirs(os.path.join(cache, "completions"), exist_ok=True)
    os.makedirs(workdir, exist_ok=True)

    script = textwrap.dedent(f"""\
        function autoload  {{ : ; }}
        function compinit  {{ : ; }}
        function zmodload  {{ : ; }}
        typeset -g -A _comps

        export ZSH="{REPO_ROOT}/"
        export HOME="{home}"
        export ZSH_CACHE_DIR="{cache}"
        export DENO_DIR="{os.path.join(tmpdir, 'deno_dir')}"
        export DENO_INSTALL_ROOT="{os.path.join(tmpdir, 'deno_install')}"

        # Change to isolated working directory
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
    env["ZSH_CACHE_DIR"] = cache
    # Strip any real Deno env from outer shell
    for k in ["DENO_DIR", "DENO_INSTALL_ROOT", "DENO_AUTH_TOKENS"]:
        env.pop(k, None)
    if extra_env:
        env.update(extra_env)

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
# Test 1 — dc: deno compile <file>
# ---------------------------------------------------------------------------

def test_dc():
    print("\n[Test 1] dc — deno compile <file>; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t045_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        result = run_zsh(tmpdir, bindir, "dc main.ts")
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("argv == ['compile', 'main.ts']", args == ["compile", "main.ts"],
              f"args={args}")
        print(f"        deno argv  : {args}")
        print(f"        workdir    : isolated tmpdir")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 2 — dca: deno cache <file>
# ---------------------------------------------------------------------------

def test_dca():
    print("\n[Test 2] dca — deno cache <file>; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t045_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        result = run_zsh(tmpdir, bindir, "dca deps.ts")
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("argv == ['cache', 'deps.ts']", args == ["cache", "deps.ts"],
              f"args={args}")
        print(f"        deno argv  : {args}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 3 — dck: deno check <file>
# ---------------------------------------------------------------------------

def test_dck():
    print("\n[Test 3] dck — deno check <file>; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t045_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        result = run_zsh(tmpdir, bindir, "dck mod.ts")
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("argv == ['check', 'mod.ts']", args == ["check", "mod.ts"],
              f"args={args}")
        print(f"        deno argv  : {args}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 4 — MISSING-DEP: deno absent → completion block skipped; aliases still defined
# ---------------------------------------------------------------------------

def test_missing_deno():
    print("\n[Test 4] MISSING-DEP — deno absent; completion skipped; aliases still defined")
    with tempfile.TemporaryDirectory(prefix="r14t045_") as tmpdir:
        # bindir has NO deno stub
        bindir = os.path.join(tmpdir, "bin")
        os.makedirs(bindir, exist_ok=True)
        _make_stub(bindir, "zf_mv", 'exit 0')

        body = textwrap.dedent("""\
            # dc alias is defined before the guard, so it must still exist
            if alias dc > /dev/null 2>&1; then
                echo "ALIAS:dc:defined"
            else
                echo "ALIAS:dc:missing"
            fi
            # completion file must NOT exist (guard returned early)
            if [[ -f "$ZSH_CACHE_DIR/completions/_deno" ]]; then
                echo "COMPLETION:exists"
            else
                echo "COMPLETION:absent"
            fi
        """)
        result = run_zsh(tmpdir, bindir, body)
        out = result.stdout

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("alias dc still defined (declared before guard)",
              "ALIAS:dc:defined" in out, f"output={out!r}")
        check("completion file absent (guard returned early)",
              "COMPLETION:absent" in out, f"output={out!r}")
        print(f"        alias dc   : {'defined' if 'ALIAS:dc:defined' in out else 'missing'}")
        print(f"        completion : {'absent (correct)' if 'COMPLETION:absent' in out else 'exists (wrong)'}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 5 — ISOLATION: DENO_DIR from outer shell does not leak into test env
# ---------------------------------------------------------------------------

def test_env_isolation():
    print("\n[Test 5] ISOLATION — outer DENO_DIR does not leak into isolated test")
    with tempfile.TemporaryDirectory(prefix="r14t045_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        # Create a fake "real" DENO_DIR that should NOT affect the test
        fake_outer_deno_dir = os.path.join(tmpdir, "outer_deno_dir")
        os.makedirs(fake_outer_deno_dir)

        body = textwrap.dedent(f"""\
            echo "DENO_DIR:$DENO_DIR"
        """)
        result = run_zsh(tmpdir, bindir, body,
                         extra_env={"DENO_DIR": fake_outer_deno_dir})
        out = result.stdout.strip()

        # The script sets DENO_DIR to tmpdir/deno_dir internally,
        # overriding any outer value
        inner_deno_dir = os.path.join(tmpdir, "deno_dir")
        # The script's export overrides the extra_env one because it runs inside zsh
        # which exports it; we confirm it's NOT the outer fake value
        reported = [l for l in out.splitlines() if l.startswith("DENO_DIR:")]
        reported_val = reported[0].split(":", 1)[1] if reported else ""

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("DENO_DIR inside test is isolated tmpdir (not outer value)",
              reported_val == inner_deno_dir,
              f"reported={reported_val!r}  outer={fake_outer_deno_dir!r}")
        print(f"        inner DENO_DIR : {reported_val!r}")
        print(f"        outer DENO_DIR : {fake_outer_deno_dir!r}")
        print(f"        isolated       : {reported_val == inner_deno_dir}")
        print(f"        exit status    : {result.returncode}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T045 · Environment-isolation tests: plugins/deno")
    print("Entry points: dc (deno compile), dca (deno cache), dck (deno check)")
    print("=" * 60)

    print("\n[Syntax] zsh -n plugins/deno/deno.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    test_dc()
    test_dca()
    test_dck()
    test_missing_deno()
    test_env_isolation()

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
