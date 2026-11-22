#!/usr/bin/env python3
"""
R14-T043 · State-transition checks for plugins/kubectl/kubectl.plugin.zsh
Entry points tested: kca (_kca), kaf, kapk

Task type: State-transition checks
Tests record the before/after state of shell functions and argv passed to
kubectl, asserting the intended change and one unrelated state that must
remain unchanged.

Tests:
  1. SUCCESS  — kca passes all args + --all-namespaces to kubectl; exit 0.
                Before: _kca function does not exist.
                After: _kca is unset (self-cleaning alias).
  2. EDGE     — kca with multiple args (e.g. get pods -n default) appends
                --all-namespaces at the end; original args preserved.
  3. SUCCESS  — kaf passes its argument as: kubectl apply -f <arg>; exit 0.
  4. SUCCESS  — kapk passes its argument as: kubectl apply -k <dir>; exit 0.
  5. BOUNDARY — unrelated alias (k=kubectl) is unchanged after kca is called.

All external commands are replaced by stubs on a temporary PATH.
No real Kubernetes cluster, kubectl binary, or user config is modified.
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
PLUGIN = os.path.join(REPO_ROOT, "plugins", "kubectl", "kubectl.plugin.zsh")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_stub(bindir: str, name: str, body: str = "") -> None:
    """Write an executable stub that logs its argv to a file."""
    p = os.path.join(bindir, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n")
        if body:
            f.write(textwrap.dedent(body))
        else:
            f.write('exit 0\n')
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def _make_bindir(tmpdir: str, argv_log: str) -> str:
    """Create stub bindir; kubectl logs its argv to argv_log."""
    bindir = os.path.join(tmpdir, "bin")
    os.makedirs(bindir, exist_ok=True)
    # kubectl stub: log every argument on a separate line, BUT skip
    # the 'completion zsh' call that the plugin fires at load time
    _make_stub(bindir, "kubectl", f"""\
        # Skip logging for the background completion-generation call
        if [ "$1" = "completion" ]; then
            exit 0
        fi
        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done
        exit 0
    """)
    # completion stub (called by plugin at load time — must succeed)
    _make_stub(bindir, "zf_mv", 'exit 0\n')
    return bindir


def run_zsh(tmpdir: str, bindir: str, body: str) -> subprocess.CompletedProcess:
    home = os.path.join(tmpdir, "home")
    cache = os.path.join(tmpdir, "cache", "completions")
    os.makedirs(home, exist_ok=True)
    os.makedirs(cache, exist_ok=True)

    script = textwrap.dedent(f"""\
        # Stub zsh builtins / modules used at plugin load time
        function autoload   {{ : ; }}
        function compinit   {{ : ; }}
        function zmodload   {{ : ; }}
        function zf_mv      {{ : ; }}

        export ZSH="{REPO_ROOT}/"
        export HOME="{home}"
        export ZSH_CACHE_DIR="{os.path.join(tmpdir, 'cache')}"
        # Pre-create the completion file so the plugin skips its generation block
        touch "{cache}/_kubectl"

        source "{PLUGIN}"

        {body}
    """)
    script_path = os.path.join(tmpdir, "script.zsh")
    with open(script_path, "w") as f:
        f.write(script)

    env = os.environ.copy()
    env["PATH"] = bindir + ":" + env.get("PATH", "")
    env["HOME"] = home
    env["ZSH_CACHE_DIR"] = os.path.join(tmpdir, "cache")
    env.pop("KUBECONFIG", None)

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
# Test 1 — kca: appends --all-namespaces; _kca unsets itself
# ---------------------------------------------------------------------------

def test_kca_all_namespaces():
    print("\n[Test 1] kca — appends --all-namespaces; _kca unset after call")
    with tempfile.TemporaryDirectory(prefix="r14t043_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent(f"""\
            # Before state: _kca must not exist
            if typeset -f _kca > /dev/null 2>&1; then
                echo "BEFORE:_kca_exists"
            else
                echo "BEFORE:_kca_absent"
            fi

            kca get pods

            # After state: _kca must have been unset
            if typeset -f _kca > /dev/null 2>&1; then
                echo "AFTER:_kca_exists"
            else
                echo "AFTER:_kca_absent"
            fi

            echo "exit_status:$?"
        """)
        result = run_zsh(tmpdir, bindir, body)
        out = result.stdout

        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []
        before_absent = "BEFORE:_kca_absent" in out
        after_absent  = "AFTER:_kca_absent"  in out

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("BEFORE: _kca function did not exist (clean state)",
              before_absent, f"output={out!r}")
        check("AFTER:  _kca unset itself (state transition complete)",
              after_absent,  f"output={out!r}")
        check("argv[0] == 'get'",  len(args) > 0 and args[0] == "get",
              f"args={args}")
        check("argv[1] == 'pods'", len(args) > 1 and args[1] == "pods",
              f"args={args}")
        check("last arg == '--all-namespaces'",
              len(args) > 0 and args[-1] == "--all-namespaces",
              f"args={args}")
        print(f"        before state : _kca absent ✓")
        print(f"        kubectl argv : {args}")
        print(f"        after  state : _kca absent ✓")
        print(f"        exit status  : {result.returncode}")


# ---------------------------------------------------------------------------
# Test 2 — kca EDGE: multiple args all forwarded, --all-namespaces last
# ---------------------------------------------------------------------------

def test_kca_multi_args():
    print("\n[Test 2] kca EDGE — multi-arg call; all args forwarded + --all-namespaces last")
    with tempfile.TemporaryDirectory(prefix="r14t043_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = "kca get pods -n default"
        result = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("arg '-n' preserved", "-n" in args, f"args={args}")
        check("arg 'default' preserved", "default" in args, f"args={args}")
        check("last arg == '--all-namespaces'",
              len(args) > 0 and args[-1] == "--all-namespaces",
              f"args={args}")
        print(f"        kubectl argv : {args}")
        print(f"        exit status  : {result.returncode}")


# ---------------------------------------------------------------------------
# Test 3 — kaf: kubectl apply -f <file>
# ---------------------------------------------------------------------------

def test_kaf():
    print("\n[Test 3] kaf — kubectl apply -f <file>; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t043_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = "kaf deployment.yaml"
        result = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("argv == ['apply', '-f', 'deployment.yaml']",
              args == ["apply", "-f", "deployment.yaml"],
              f"args={args}")
        print(f"        kubectl argv : {args}")
        print(f"        exit status  : {result.returncode}")


# ---------------------------------------------------------------------------
# Test 4 — kapk: kubectl apply -k <dir>
# ---------------------------------------------------------------------------

def test_kapk():
    print("\n[Test 4] kapk — kubectl apply -k <dir>; exit 0")
    with tempfile.TemporaryDirectory(prefix="r14t043_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = "kapk ./overlays/prod"
        result = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("argv == ['apply', '-k', './overlays/prod']",
              args == ["apply", "-k", "./overlays/prod"],
              f"args={args}")
        print(f"        kubectl argv : {args}")
        print(f"        exit status  : {result.returncode}")


# ---------------------------------------------------------------------------
# Test 5 — BOUNDARY: unrelated alias k=kubectl unchanged after kca call
# ---------------------------------------------------------------------------

def test_unrelated_alias_unchanged():
    print("\n[Test 5] BOUNDARY — alias k=kubectl unchanged after kca is called")
    with tempfile.TemporaryDirectory(prefix="r14t043_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            # Record k alias before
            k_before=$(alias k 2>/dev/null)

            kca version

            # Record k alias after
            k_after=$(alias k 2>/dev/null)

            echo "k_before:$k_before"
            echo "k_after:$k_after"
            [[ "$k_before" == "$k_after" ]] && echo "UNCHANGED" || echo "CHANGED"
        """)
        result = run_zsh(tmpdir, bindir, body)
        out = result.stdout

        check("exit status 0", result.returncode == 0,
              f"rc={result.returncode} stderr={result.stderr.strip()!r}")
        check("alias k unchanged after kca call", "UNCHANGED" in out,
              f"output={out!r}")
        k_line = [l for l in out.splitlines() if l.startswith("k_before:")]
        print(f"        k alias before : {k_line[0] if k_line else 'n/a'}")
        print(f"        k alias after  : {'unchanged' if 'UNCHANGED' in out else 'CHANGED'}")
        print(f"        exit status    : {result.returncode}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T043 · State-transition checks: plugins/kubectl")
    print("Entry points: kca (_kca), kaf, kapk")
    print("=" * 60)

    print("\n[Syntax] zsh -n plugins/kubectl/kubectl.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    test_kca_all_namespaces()
    test_kca_multi_args()
    test_kaf()
    test_kapk()
    test_unrelated_alias_unchanged()

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
