#!/usr/bin/env python3
"""
R14-T041 · Command-contract tests for plugins/node/node.plugin.zsh
Entry point tested: node-docs

Checks:
  1. SUCCESS  — node-docs with a section argument builds the correct URL and
                passes it to the open command; exit status 0.
  2. EDGE     — node-docs with NO argument defaults to 'all' and builds the
                correct URL; exit status 0.
  3. FAILURE  — when 'node' is absent (empty stub that returns nothing) the
                URL still contains "undefined" or the function exits non-zero;
                we assert that the URL is NOT silently built from an empty
                version string (guard against regression).

All external commands (node, open/xdg-open/open_command) are replaced by
stubs on a temporary PATH. No real Node.js installation or browser is
required, and no user configuration is modified.
"""

import os
import stat
import subprocess
import sys
import tempfile
import textwrap

PLUGIN = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),   # work/R14-T041/
    "..", "..",                                     # repo root
    "plugins", "node", "node.plugin.zsh",
)
PLUGIN = os.path.normpath(PLUGIN)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_stub(dir_path: str, name: str, script: str) -> str:
    """Write an executable stub script and return its path."""
    p = os.path.join(dir_path, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n")
        f.write(textwrap.dedent(script))
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return p


def run_in_zsh(tmpdir: str, zsh_body: str) -> subprocess.CompletedProcess:
    """
    Run zsh_body in a minimal zsh session that sources node.plugin.zsh.
    The tmpdir/bin directory is prepended to PATH so stubs shadow real tools.
    Returns the CompletedProcess result.
    """
    script = textwrap.dedent(f"""\
        # Minimal bootstrap — no user dotfiles
        export ZSH="{os.path.normpath(os.path.join(PLUGIN, '../../..'))}/"
        export HOME="{tmpdir}/home"
        mkdir -p "$HOME"

        # Source the plugin under test
        source "{PLUGIN}"

        # Execute the test body
        {zsh_body}
    """)
    script_path = os.path.join(tmpdir, "test_script.zsh")
    with open(script_path, "w") as f:
        f.write(script)

    env = os.environ.copy()
    env["PATH"] = os.path.join(tmpdir, "bin") + ":" + env.get("PATH", "")
    env["HOME"] = os.path.join(tmpdir, "home")

    return subprocess.run(
        ["zsh", "--no-rcs", "--no-globalrcs", script_path],
        capture_output=True, text=True, env=env,
    )


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"
failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  {PASS}  {label}")
    else:
        failures.append(label)
        msg = f"  {FAIL}  {label}"
        if detail:
            msg += f"\n        detail: {detail}"
        print(msg)


# ---------------------------------------------------------------------------
# Test 1 — SUCCESS: section argument builds correct URL
# ---------------------------------------------------------------------------

def test_with_section():
    print("\n[Test 1] node-docs <section> → correct URL passed to open_command")
    with tempfile.TemporaryDirectory(prefix="r14t041_") as tmpdir:
        bindir = os.path.join(tmpdir, "bin")
        os.makedirs(bindir)

        # Stub: node --version → v20.11.0
        _make_stub(bindir, "node", """\
            case "$1" in
              --version) echo "v20.11.0" ;;
            esac
        """)

        # Stub: open_command logs its argument to a file
        url_file = os.path.join(tmpdir, "captured_url.txt")
        _make_stub(bindir, "open", f'echo "$1" > "{url_file}"\n')
        # Also cover xdg-open (Linux)
        _make_stub(bindir, "xdg-open", f'echo "$1" > "{url_file}"\n')

        # Override open_command to use our stub
        body = textwrap.dedent(f"""\
            # Redefine open_command so it writes the URL to a file
            function open_command {{ echo "$1" > "{url_file}" }}
            node-docs fs
        """)

        result = run_in_zsh(tmpdir, body)
        exit_ok = result.returncode == 0
        check("exit status 0", exit_ok,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")

        url = open(url_file).read().strip() if os.path.exists(url_file) else ""
        expected_fragment = "v20.11.0/api/fs.html"
        url_ok = expected_fragment in url
        check(f"URL contains '{expected_fragment}'", url_ok,
              f"actual url={url!r}")

        # Report actual arguments for evidence
        print(f"        actual URL : {url!r}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 2 — EDGE: no argument defaults to 'all'
# ---------------------------------------------------------------------------

def test_default_section():
    print("\n[Test 2] node-docs (no args) → defaults to 'all' section")
    with tempfile.TemporaryDirectory(prefix="r14t041_") as tmpdir:
        bindir = os.path.join(tmpdir, "bin")
        os.makedirs(bindir)

        _make_stub(bindir, "node", """\
            case "$1" in
              --version) echo "v18.0.0" ;;
            esac
        """)

        url_file = os.path.join(tmpdir, "captured_url.txt")

        body = textwrap.dedent(f"""\
            function open_command {{ echo "$1" > "{url_file}" }}
            node-docs     # no argument
        """)

        result = run_in_zsh(tmpdir, body)
        exit_ok = result.returncode == 0
        check("exit status 0", exit_ok,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")

        url = open(url_file).read().strip() if os.path.exists(url_file) else ""
        expected_fragment = "v18.0.0/api/all.html"
        url_ok = expected_fragment in url
        check(f"URL defaults to 'all.html' (fragment: '{expected_fragment}')", url_ok,
              f"actual url={url!r}")

        print(f"        actual URL : {url!r}")
        print(f"        exit status: {result.returncode}")


# ---------------------------------------------------------------------------
# Test 3 — FAILURE / EDGE: 'node' binary absent → URL must not be silently
#           built with an empty version string (empty string is a regression)
# ---------------------------------------------------------------------------

def test_missing_node():
    print("\n[Test 3] node absent → URL is not silently built with empty version")
    with tempfile.TemporaryDirectory(prefix="r14t041_") as tmpdir:
        bindir = os.path.join(tmpdir, "bin")
        os.makedirs(bindir)

        # NO node stub — 'node' is unavailable on this PATH

        url_file = os.path.join(tmpdir, "captured_url.txt")
        # Write a sentinel so we can detect if open_command was never called
        with open(url_file, "w") as f:
            f.write("__NOT_CALLED__")

        body = textwrap.dedent(f"""\
            function open_command {{ echo "$1" > "{url_file}" }}
            node-docs http 2>/dev/null || true
        """)

        result = run_in_zsh(tmpdir, body)
        url = open(url_file).read().strip() if os.path.exists(url_file) else "__NOT_CALLED__"

        # The contract we assert: if open_command IS called, the URL must
        # not contain an empty version segment (i.e. "//api/" or "/docs//api/")
        if url == "__NOT_CALLED__":
            check("open_command not called (graceful no-op when node missing)", True)
        else:
            # open_command was called; ensure no empty version segment
            bad_url = "//api/" in url or "/docs//api/" in url or "/docs/undefined/" in url
            check("URL does not contain empty/undefined version segment", not bad_url,
                  f"actual url={url!r}")

        print(f"        URL received : {url!r}")
        print(f"        exit status  : {result.returncode}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T041 · Command-contract tests: plugins/node/node-docs")
    print("=" * 60)

    # First: syntax check the plugin
    print("\n[Syntax] zsh -n plugins/node/node.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    # Run the three contract tests
    test_with_section()
    test_default_section()
    test_missing_node()

    # Summary
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
