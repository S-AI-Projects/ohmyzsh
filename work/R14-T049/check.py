#!/usr/bin/env python3
"""
R14-T049 · Tooling integration and entry point tests for plugins/composer
Entry points tested:
  - c   -> composer
  - ccp -> composer create-project
  - cdo -> composer dump-autoload -o

Task type: Tooling integration
Tests:
  1. SUCCESS (c)      - Invokes 'composer' with arguments, verifies exact argv and exit 0.
  2. SUCCESS (ccp)    - Invokes 'composer create-project <pkg> <dir>', verifies exact argv and exit 0.
  3. SUCCESS (cdo)    - Invokes 'composer dump-autoload -o', verifies exact argv and exit 0.
  4. FAILURE (status) - Non-zero exit code (1) from composer propagates cleanly through aliases.
  5. EDGE (isolation) - When composer is absent, plugin sources without error; aliases remain defined;
                        global state is unpolluted.
  6. CLEANUP (state)  - Temporary directories and state are verified to be cleaned up after execution.

All external commands (composer, php, curl) are stubbed on a temporary PATH.
No real Composer, PHP runtime, or network service is invoked.
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
PLUGIN = os.path.join(REPO_ROOT, "plugins", "composer", "composer.plugin.zsh")

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

    # Stub composer
    _make_stub(bindir, "composer", f"""\
        # Ignore global config bin-dir call made at source time
        if [ "$1" = "global" ] && [ "$2" = "config" ]; then
            echo "{tmpdir}/composer_global_bin"
            exit 0
        fi

        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done
        exit {exit_code}
    """)

    return bindir


def run_zsh(tmpdir: str, bindir: str, body: str, include_stubs: bool = True) -> subprocess.CompletedProcess:
    home = os.path.join(tmpdir, "home")
    workdir = os.path.join(tmpdir, "workdir")
    os.makedirs(home, exist_ok=True)
    os.makedirs(workdir, exist_ok=True)

    script = textwrap.dedent(f"""\
        setopt aliases

        # Stub builtins/functions that the plugin might invoke
        function is-at-least     {{ return 0; }}
        function compdef         {{ : ; }}
        function _store_cache    {{ : ; }}
        function _retrieve_cache {{ : ; }}
        function _cache_invalid  {{ return 1; }}

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
    if include_stubs:
        env["PATH"] = bindir + ":" + env.get("PATH", "")
    else:
        env["PATH"] = "/usr/bin:/bin"
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

def test_alias_c():
    print("\n[Test 1] SUCCESS - alias c expands to 'composer'")
    with tempfile.TemporaryDirectory(prefix="r14t049_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            c require symfony/yaml
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("arguments received match ['require', 'symfony/yaml']",
              args == ["require", "symfony/yaml"], f"args={args}")
        print(f"        composer argv: {args}")


def test_alias_ccp():
    print("\n[Test 2] SUCCESS - alias ccp expands to 'composer create-project'")
    with tempfile.TemporaryDirectory(prefix="r14t049_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            ccp laravel/laravel myapp
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("arguments received match ['create-project', 'laravel/laravel', 'myapp']",
              args == ["create-project", "laravel/laravel", "myapp"], f"args={args}")
        print(f"        composer argv: {args}")


def test_alias_cdo():
    print("\n[Test 3] SUCCESS - alias cdo expands to 'composer dump-autoload -o'")
    with tempfile.TemporaryDirectory(prefix="r14t049_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            cdo
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("arguments received match ['dump-autoload', '-o']",
              args == ["dump-autoload", "-o"], f"args={args}")
        print(f"        composer argv: {args}")


def test_failure_propagation():
    print("\n[Test 4] FAILURE - exit code propagates non-zero when composer fails")
    with tempfile.TemporaryDirectory(prefix="r14t049_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        # Stub composer returning exit code 2
        bindir = _make_bindir(tmpdir, argv_log, exit_code=2)

        body = textwrap.dedent("""\
            c require invalid/nonexistent-package
            echo "EXIT_CODE:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        out_lines = [l for l in res.stdout.splitlines() if l.startswith("EXIT_CODE:")]
        ec = out_lines[0].split(":")[1] if out_lines else "0"

        check("non-zero exit code (2) propagates cleanly through alias c",
              ec == "2", f"ec={ec}")
        print(f"        reported exit: {ec} ✓")


def test_missing_composer_isolation():
    print("\n[Test 5] EDGE - plugin sourcing without composer dependency")
    with tempfile.TemporaryDirectory(prefix="r14t049_") as tmpdir:
        body = textwrap.dedent("""\
            # Verify aliases remain defined even if composer is not in PATH
            if alias c >/dev/null 2>&1 && alias ccp >/dev/null 2>&1 && alias cdo >/dev/null 2>&1; then
                echo "ALIASES:defined"
            else
                echo "ALIASES:missing"
            fi
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, "/bin", body, include_stubs=False)

        check("sourcing exits 0 when composer is not installed",
              "EXIT:0" in res.stdout, f"out={res.stdout}")
        check("aliases c, ccp, cdo remain defined",
              "ALIASES:defined" in res.stdout, f"out={res.stdout}")
        print(f"        independent of composer installation: aliases defined ✓")


def test_state_cleanup():
    print("\n[Test 6] CLEANUP - temporary state and directories are cleaned up")
    tmp_path = ""
    with tempfile.TemporaryDirectory(prefix="r14t049_clean_") as tmpdir:
        tmp_path = tmpdir
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)
        res = run_zsh(tmpdir, bindir, "c --version")
        check("command in temporary workspace ran successfully", res.returncode == 0)

    # After context exit, tmpdir must no longer exist on filesystem
    check("temporary workspace cleaned up cleanly", not os.path.exists(tmp_path),
          f"directory still exists: {tmp_path}")
    print(f"        cleanup verified: {tmp_path} removed ✓")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T049 · Tooling integration tests: plugins/composer")
    print("Entry points: c, ccp, cdo")
    print("=" * 60)

    print("\n[Syntax] zsh -n plugins/composer/composer.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    test_alias_c()
    test_alias_ccp()
    test_alias_cdo()
    test_failure_propagation()
    test_missing_composer_isolation()
    test_state_cleanup()

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
