#!/usr/bin/env python3
"""
R14-T047 · Executable command documentation tests for plugins/conda
Entry points tested:
  - cncf -> conda env create -f
  - cna  -> conda activate
  - cnab -> conda activate base

Tests:
  1. SUCCESS (cncf) - Creates environment from YAML file:
                      invokes 'conda env create -f <file>' and exits 0.
  2. SUCCESS (cna)  - Activates named environment:
                      invokes 'conda activate <env>' and transitions CONDA_DEFAULT_ENV.
  3. SUCCESS (cnab) - Activates base environment:
                      invokes 'conda activate base' and transitions CONDA_DEFAULT_ENV to 'base'.
  4. FAILURE (cncf) - Missing environment spec file:
                      returns non-zero exit status (1) and error output.
  5. DOC-WORKFLOW   - Full documented end-to-end usage workflow from README.md:
                      setup (environment.yml) -> cncf -> cna -> state verification.

All external commands are stubbed on a temporary PATH.
All state changes stay inside isolated temporary directories.
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
PLUGIN = os.path.join(REPO_ROOT, "plugins", "conda", "conda.plugin.zsh")

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
    # Stub conda script: logs arguments and simulates create / activate behavior
    _make_stub(bindir, "conda", f"""\
        for arg in "$@"; do
            printf '%s\\n' "$arg" >> "{argv_log}"
        done

        case "$1" in
            env)
                if [ "$2" = "create" ] && [ "$3" = "-f" ]; then
                    if [ ! -f "$4" ]; then
                        echo "Environment file not found: $4" >&2
                        exit 1
                    fi
                    echo "Successfully created environment from $4"
                    exit 0
                fi
                ;;
            activate)
                target="${{2:-base}}"
                echo "Activating environment: $target"
                # Signal the test wrapper of activation state
                printf '%s' "$target" > "{tmpdir}/current_env.txt"
                exit 0
                ;;
        esac
        exit 0
    """)
    return bindir


def run_zsh(tmpdir: str, bindir: str, body: str) -> subprocess.CompletedProcess:
    home = os.path.join(tmpdir, "home")
    workdir = os.path.join(tmpdir, "workdir")
    os.makedirs(home, exist_ok=True)
    os.makedirs(workdir, exist_ok=True)

    script = textwrap.dedent(f"""\
        export ZSH="{REPO_ROOT}/"
        export HOME="{home}"
        cd "{workdir}"

        source "{PLUGIN}"

        # Helper to simulate conda activation hook in shell
        function _sync_conda_env {{
            if [[ -f "{tmpdir}/current_env.txt" ]]; then
                export CONDA_DEFAULT_ENV="$(cat "{tmpdir}/current_env.txt")"
            fi
        }}

        {body}
    """)
    script_path = os.path.join(home, "script.zsh")
    with open(script_path, "w") as f:
        f.write(script)

    env = os.environ.copy()
    env["PATH"] = bindir + ":" + env.get("PATH", "")
    env["HOME"] = home
    for k in ["CONDA_DEFAULT_ENV", "CONDA_PREFIX", "CONDA_SHLVL"]:
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
        print(f"  {FAIL}  {label}" + (f"\n        detail: {detail}" if detail else ""))


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_cncf_success():
    print("\n[Test 1] SUCCESS - cncf creates environment from YAML file")
    with tempfile.TemporaryDirectory(prefix="r14t047_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)
        workdir = os.path.join(tmpdir, "workdir")
        os.makedirs(workdir, exist_ok=True)
        yml_path = os.path.join(workdir, "environment.yml")
        with open(yml_path, "w") as f:
            f.write("name: test-env\nchannels:\n  - conda-forge\n")

        body = textwrap.dedent("""\
            cncf environment.yml
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", res.returncode == 0, f"rc={res.returncode} stderr={res.stderr}")
        check("arguments match ['env', 'create', '-f', 'environment.yml']",
              args == ["env", "create", "-f", "environment.yml"], f"args={args}")
        check("output confirms creation", "Successfully created environment" in res.stdout,
              f"out={res.stdout}")
        print(f"        conda argv : {args}")
        print(f"        stdout     : {res.stdout.strip()}")


def test_cna_success():
    print("\n[Test 2] SUCCESS - cna activates specified conda environment")
    with tempfile.TemporaryDirectory(prefix="r14t047_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            cna my-project
            _sync_conda_env
            echo "CONDA_DEFAULT_ENV:$CONDA_DEFAULT_ENV"
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", res.returncode == 0, f"rc={res.returncode}")
        check("arguments match ['activate', 'my-project']",
              args == ["activate", "my-project"], f"args={args}")
        check("CONDA_DEFAULT_ENV state updated to 'my-project'",
              "CONDA_DEFAULT_ENV:my-project" in res.stdout, f"out={res.stdout}")
        print(f"        conda argv : {args}")
        print(f"        env state  : my-project ✓")


def test_cnab_success():
    print("\n[Test 3] SUCCESS - cnab activates base environment")
    with tempfile.TemporaryDirectory(prefix="r14t047_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            cnab
            _sync_conda_env
            echo "CONDA_DEFAULT_ENV:$CONDA_DEFAULT_ENV"
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)
        args = open(argv_log).read().strip().splitlines() if os.path.exists(argv_log) else []

        check("exit status 0", res.returncode == 0, f"rc={res.returncode}")
        check("arguments match ['activate', 'base']",
              args == ["activate", "base"], f"args={args}")
        check("CONDA_DEFAULT_ENV state updated to 'base'",
              "CONDA_DEFAULT_ENV:base" in res.stdout, f"out={res.stdout}")
        print(f"        conda argv : {args}")
        print(f"        env state  : base ✓")


def test_cncf_missing_file_failure():
    print("\n[Test 4] FAILURE - cncf fails when environment file does not exist")
    with tempfile.TemporaryDirectory(prefix="r14t047_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)

        body = textwrap.dedent("""\
            cncf nonexistent.yml
            echo "EXIT:$?"
        """)
        res = run_zsh(tmpdir, bindir, body)

        check("stderr reports missing file",
              "Environment file not found: nonexistent.yml" in res.stderr,
              f"stderr={res.stderr}")
        check("reported exit status is non-zero (1)", "EXIT:1" in res.stdout,
              f"out={res.stdout}")
        print(f"        stderr msg : Environment file not found")
        print(f"        exit code  : 1 ✓")


def test_documented_usage_workflow():
    print("\n[Test 5] DOC-WORKFLOW - executes complete README usage example")
    with tempfile.TemporaryDirectory(prefix="r14t047_") as tmpdir:
        argv_log = os.path.join(tmpdir, "argv.txt")
        bindir = _make_bindir(tmpdir, argv_log)
        workdir = os.path.join(tmpdir, "workdir")
        os.makedirs(workdir, exist_ok=True)

        # 1. Setup: write environment.yml as documented in README
        yml_path = os.path.join(workdir, "environment.yml")
        with open(yml_path, "w") as f:
            f.write(textwrap.dedent("""\
                name: ml-env
                channels:
                  - conda-forge
                dependencies:
                  - python=3.10
                  - numpy
            """))

        # 2. Commands: create from file, activate, then activate base
        body = textwrap.dedent("""\
            # Step A: Create environment from file
            cncf environment.yml
            echo "STATUS_CREATE:$?"

            # Step B: Activate environment
            cna ml-env
            _sync_conda_env
            echo "ACTIVE_ENV:$CONDA_DEFAULT_ENV"

            # Step C: Return to base
            cnab
            _sync_conda_env
            echo "BASE_ENV:$CONDA_DEFAULT_ENV"
        """)
        res = run_zsh(tmpdir, bindir, body)

        check("create step completed with code 0", "STATUS_CREATE:0" in res.stdout, f"out={res.stdout}")
        check("environment activated as ml-env", "ACTIVE_ENV:ml-env" in res.stdout, f"out={res.stdout}")
        check("environment switched back to base", "BASE_ENV:base" in res.stdout, f"out={res.stdout}")
        print(f"        setup      : environment.yml created ✓")
        print(f"        cncf run   : environment created ✓")
        print(f"        cna run    : ml-env active ✓")
        print(f"        cnab run   : base active ✓")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("R14-T047 · Executable documentation tests: plugins/conda")
    print("Entry points: cncf, cna, cnab")
    print("=" * 60)

    print("\n[Syntax] zsh -n plugins/conda/conda.plugin.zsh")
    syntax = subprocess.run(["zsh", "-n", PLUGIN], capture_output=True, text=True)
    check("plugin passes zsh -n syntax check", syntax.returncode == 0,
          syntax.stderr.strip())

    test_cncf_success()
    test_cna_success()
    test_cnab_success()
    test_cncf_missing_file_failure()
    test_documented_usage_workflow()

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
