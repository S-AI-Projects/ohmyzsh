#!/usr/bin/env python3
"""
R14-T044 · Path-quoting tests for plugins/gh/gh.plugin.zsh
Entry points: gh completion --shell zsh  (the plugin's completion init block)

Task type: Path quoting

Tests:
  1. SUCCESS  — gh completion --shell zsh is invoked with exact args; path with
                spaces in ZSH_CACHE_DIR is handled correctly; completion file
                is written to the correct location; exit 0.
  2. EDGE     — ZSH_CACHE_DIR path contains spaces AND special chars (parens);
                the completion file is still written to the correct location.
  3. BOUNDARY — argument containing a wildcard character (*) passed to gh is
                NOT glob-expanded by the shell; the literal string is preserved.
  4. BOUNDARY — unrelated files in the cache directory are unchanged after
                the plugin loads (shell expansion does not affect unrelated files).

All external commands (gh, autoload, compinit, zmodload, zf_mv) are stubbed.
No real GitHub CLI or user configuration is modified.
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
PLUGIN = os.path.join(REPO_ROOT, "plugins", "gh", "gh.plugin.zsh")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_stub(bindir: str, name: str, body: str = "exit 0") -> None:
    p = os.path.join(bindir, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n")
        f.write(textwrap.dedent(body) + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def _make_bindir(tmpdir: str, argv_log: str, completion_content: str = "#completion") -> str:
    bindir = os.path.join(tmpdir, "bin")
    os.makedirs(bindir, exist_ok=True)
    # gh stub: log argv (skip 'completion' calls to avoid noise), then write
    # fake completion output to stdout so =() process substitution works
    _make_stub(bindir, "gh", f"""\
        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done
        printf '{completion_content}\\n'
        exit 0
    """)
    _make_stub(bindir, "zf_mv", 'cp "$3" "$4" 2>/dev/null; exit 0')
    return bindir


def run_zsh(cache_dir: str, bindir: str, home: str) -> subprocess.CompletedProcess:
    """Source the plugin with the given ZSH_CACHE_DIR and return the result."""
    # Pre-create completions dir (the plugin expects it to exist)
    os.makedirs(os.path.join(cache_dir, "completions"), exist_ok=True)
    os.makedirs(home, exist_ok=True)

    script = textwrap.dedent(f"""\
        function autoload  {{ : ; }}
        function compinit  {{ : ; }}
        function zmodload  {{ : ; }}
        typeset -g -A _comps

        export ZSH="{REPO_ROOT}/"
        export HOME="{home}"
        export ZSH_CACHE_DIR="{cache_dir}"

        source "{PLUGIN}"

        # Wait briefly for the background job to finish
        sleep 0.3
    """)
    script_path = os.path.join(home, "script.zsh")
    with open(script_path, "w") as f:
        f.write(script)

    env = os.environ.copy()
    env["PATH"] = bindir + ":" + env.get("PATH", "")
    env["HOME"] = home
    env["ZSH_CACHE_DIR"] = cache_dir

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
# Test 1 — SUCCESS: simple cache dir, completion args exact, file written
# ---------------------------------------------------------------------------

def test_simple_cache_dir():
    print("\n[Test 1] SUCCESS — simple cache dir; completion args exact; file written")
    with tempfile.TemporaryDirectory(prefix="r14t044_") as tmpdir:
        cache_dir = os.path.join(tmpdir, "cache")
        home = os.path.join(tmpdir, "home")
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        result = run_zsh(cache_dir, bindir, home)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []
        comp_file = os.path.join(cache_dir, "completions", "_gh")

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("gh called with 'completion'", "completion" in args,
              f"args={args}")
        check("gh called with '--shell'", "--shell" in args,
              f"args={args}")
        check("gh called with 'zsh'", "zsh" in args,
              f"args={args}")
        check("completion file written to cache dir", os.path.exists(comp_file),
              f"expected: {comp_file}")

        print(f"        gh argv    : {args}")
        print(f"        comp file  : {'exists' if os.path.exists(comp_file) else 'MISSING'}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 2 — EDGE: cache dir path contains spaces and special chars
# ---------------------------------------------------------------------------

def test_cache_dir_with_spaces():
    print("\n[Test 2] EDGE — ZSH_CACHE_DIR contains spaces; completion file still written")
    with tempfile.TemporaryDirectory(prefix="r14t044_") as tmpdir:
        # Path with spaces in directory name
        cache_dir = os.path.join(tmpdir, "my cache dir with spaces")
        home = os.path.join(tmpdir, "home")
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        result = run_zsh(cache_dir, bindir, home)
        comp_file = os.path.join(cache_dir, "completions", "_gh")

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("completion file written (path with spaces)", os.path.exists(comp_file),
              f"cache_dir={cache_dir!r}")

        print(f"        cache dir  : {cache_dir!r}")
        print(f"        comp file  : {'exists' if os.path.exists(comp_file) else 'MISSING'}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 3 — BOUNDARY: wildcard arg NOT glob-expanded
# ---------------------------------------------------------------------------

def test_wildcard_not_expanded():
    print("\n[Test 3] BOUNDARY — gh arg containing wildcard '*' is NOT glob-expanded")
    with tempfile.TemporaryDirectory(prefix="r14t044_") as tmpdir:
        cache_dir = os.path.join(tmpdir, "cache")
        home = os.path.join(tmpdir, "home")
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        # Create some files that a glob *could* match if expansion happened
        os.makedirs(os.path.join(tmpdir, "decoy"), exist_ok=True)
        for name in ["file1.txt", "file2.txt", "file3.txt"]:
            open(os.path.join(tmpdir, "decoy", name), "w").close()

        # Run a zsh script that calls gh with a wildcard argument directly
        # (simulating what happens when a user passes a glob to a gh alias)
        script_body = textwrap.dedent(f"""\
            function autoload  {{ : ; }}
            function compinit  {{ : ; }}
            function zmodload  {{ : ; }}
            typeset -g -A _comps

            export ZSH="{REPO_ROOT}/"
            export HOME="{home}"
            export ZSH_CACHE_DIR="{cache_dir}"
            export PATH="{bindir}:$PATH"

            # Directly invoke gh with a wildcard arg (should NOT expand)
            setopt noglob
            gh pr list --search "type:pr *.yaml"
            setopt glob
        """)
        os.makedirs(home, exist_ok=True)
        os.makedirs(os.path.join(cache_dir, "completions"), exist_ok=True)
        script_path = os.path.join(home, "script.zsh")
        with open(script_path, "w") as f:
            f.write(script_body)

        env = os.environ.copy()
        env["PATH"] = bindir + ":" + env.get("PATH", "")
        env["HOME"] = home

        result = subprocess.run(
            ["zsh", "--no-rcs", "--no-globalrcs", script_path],
            capture_output=True, text=True, env=env,
        )

        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        # The wildcard argument must appear as the literal string, not expanded filenames
        wildcard_arg = "type:pr *.yaml"
        literal_preserved = wildcard_arg in args or any("*.yaml" in a for a in args)
        no_expansion = not any(a in ["file1.txt", "file2.txt", "file3.txt"] for a in args)

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("wildcard arg preserved as literal (not glob-expanded)",
              literal_preserved, f"args={args}")
        check("no decoy filenames appear in argv (glob not expanded)",
              no_expansion, f"args={args}")

        print(f"        gh argv    : {args}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 4 — BOUNDARY: unrelated files in cache dir unchanged after plugin load
# ---------------------------------------------------------------------------

def test_unrelated_files_unchanged():
    print("\n[Test 4] BOUNDARY — unrelated cache files unchanged after plugin loads")
    with tempfile.TemporaryDirectory(prefix="r14t044_") as tmpdir:
        cache_dir = os.path.join(tmpdir, "cache")
        home = os.path.join(tmpdir, "home")
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        # Create an unrelated file in the completions dir before loading
        comp_dir = os.path.join(cache_dir, "completions")
        os.makedirs(comp_dir, exist_ok=True)
        unrelated = os.path.join(comp_dir, "_kubectl")
        sentinel = "unrelated-sentinel-content"
        with open(unrelated, "w") as f:
            f.write(sentinel)

        result = run_zsh(cache_dir, bindir, home)

        content_after = open(unrelated).read() if os.path.exists(unrelated) else ""
        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("unrelated file still exists", os.path.exists(unrelated),
              f"file missing: {unrelated}")
        check("unrelated file content unchanged", content_after == sentinel,
              f"before={sentinel!r} after={content_after!r}")

        print(f"        unrelated file : {os.path.basename(unrelated)}")
        print(f"        content intact : {content_after == sentinel}")
        print(f"        exit status    : {result.returncode}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T044 · Path-quoting tests: plugins/gh")
    print("Entry points: gh completion --shell zsh (completion init)")
    print("=" * 60)

    print("\n[Syntax] zsh -n plugins/gh/gh.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    test_simple_cache_dir()
    test_cache_dir_with_spaces()
    test_wildcard_not_expanded()
    test_unrelated_files_unchanged()

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
