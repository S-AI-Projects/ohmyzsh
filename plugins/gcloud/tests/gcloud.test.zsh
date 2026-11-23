#!/usr/bin/env zsh
# ==============================================================================
# Oh My Zsh - gcloud plugin isolated fixture & regression test suite
# Task: R14-T060 (Protect a condition with a regression: gcloud)
# ==============================================================================

emulate -LR zsh
setopt aliases

# Resolve plugin path (supports external override for mutation testing)
local plugin_file="${GCLOUD_PLUGIN_PATH:-${0:A:h:h}/gcloud.plugin.zsh}"
if [[ -n "$1" ]]; then
  plugin_file="$1"
fi

if [[ ! -f "$plugin_file" ]]; then
  print -u2 -r -- "FAIL: Cannot find gcloud.plugin.zsh at $plugin_file"
  exit 1
fi

local test_dir=$(mktemp -d) || exit 1
trap 'command rm -rf -- "$test_dir"' EXIT INT TERM

# Ensure environment isolation
export ZDOTDIR="$test_dir/zdotdir"
export HOME="$test_dir/home"
export TMPDIR="$test_dir/tmp"
export ZSH="${ZSH:-${0:A:h:h:h:h}}"
mkdir -p "$ZDOTDIR" "$HOME" "$TMPDIR" "$test_dir/logs"

# Host Python resolution (absolute path to avoid PATH recursion)
local host_python="${PYTHON_BIN:-${commands[python3]:-$(command -v python3 2>/dev/null)}}"
if [[ -z "$host_python" || ! -x "$host_python" ]]; then
  print -u2 -r -- "FAIL: Python 3 executable not found"
  exit 1
fi

# Create shared stub runner for gcloud command
local stub_runner="$test_dir/mock_gcloud_runner.py"
cat << EOF > "$stub_runner"
#!$host_python
import sys, json, os

cmd_name = os.path.basename(sys.argv[0])
args = sys.argv[1:]

log_file = os.environ.get("STUB_CALL_LOG_GCLOUD")
if log_file:
    data = {"command": cmd_name, "args": args}
    with open(log_file, "w", encoding="utf-8") as f:
        json.dump(data, f)

if "--invalid-flag" in args:
    sys.stderr.write(f"ERROR: (gcloud) unrecognized argument: --invalid-flag\\n")
    sys.exit(2)

if "--version" in args:
    sys.stdout.write("Google Cloud SDK 480.0.0\\n")
    sys.exit(0)

sys.stdout.write(f"mock-gcloud executed: {' '.join(args)}\\n")
sys.exit(0)
EOF
chmod +x "$stub_runner"

local total_tests=0
local passed_tests=0
local failed_tests=0

run_test() {
  local test_name="$1"
  local test_desc="$2"
  shift 2
  total_tests=$(( total_tests + 1 ))

  # Run test block in isolated subshell
  local out
  local err
  local rc
  local out_file="$test_dir/test_${test_name}.out"
  local err_file="$test_dir/test_${test_name}.err"

  zsh -df -c "$*" > "$out_file" 2> "$err_file"
  rc=$?
  out=$(<"$out_file")
  err=$(<"$err_file")

  if (( rc == 0 )); then
    passed_tests=$(( passed_tests + 1 ))
    print -r -- "PASS [$test_name] $test_desc"
  else
    failed_tests=$(( failed_tests + 1 ))
    print -u2 -r -- "FAIL [$test_name] $test_desc (exit: $rc)"
    if [[ -n "$out" ]]; then
      print -u2 -r -- "  stdout: $out"
    fi
    if [[ -n "$err" ]]; then
      print -u2 -r -- "  stderr: $err"
    fi
  fi
}

# ==============================================================================
# Test Cases
# ==============================================================================

# T01: Auto-discovery when CLOUDSDK_HOME is unset
run_test "T01_auto_discovery_standard_path" \
  "Auto-discovery: discovers SDK in standard path when CLOUDSDK_HOME is unset" \
  '
    local mock_sdk="'$test_dir'/home/google-cloud-sdk"
    mkdir -p "$mock_sdk/bin"
    touch "$mock_sdk/path.zsh.inc"
    touch "$mock_sdk/completion.zsh.inc"
    cp "'$stub_runner'" "$mock_sdk/bin/gcloud"
    chmod +x "$mock_sdk/bin/gcloud"

    unset CLOUDSDK_HOME
    export HOME="'$test_dir'/home"
    source "'$plugin_file'" || exit 1

    [[ "$CLOUDSDK_HOME" == "$mock_sdk" ]] || {
      echo "Expected CLOUDSDK_HOME to be $mock_sdk, got $CLOUDSDK_HOME"
      exit 1
    }
  '

# T02: Custom CLOUDSDK_HOME is preserved (not overwritten by discovery loop)
run_test "T02_custom_cloudsdk_home_preserved" \
  "Option preservation: pre-configured CLOUDSDK_HOME is respected and not overwritten" \
  '
    local std_sdk="'$test_dir'/home/google-cloud-sdk"
    mkdir -p "$std_sdk"
    local custom_sdk="'$test_dir'/custom_sdk_dir"
    mkdir -p "$custom_sdk/bin"
    touch "$custom_sdk/path.zsh.inc"

    export HOME="'$test_dir'/home"
    export CLOUDSDK_HOME="$custom_sdk"
    source "'$plugin_file'" || exit 1

    [[ "$CLOUDSDK_HOME" == "$custom_sdk" ]] || {
      echo "Expected CLOUDSDK_HOME to remain $custom_sdk, got $CLOUDSDK_HOME"
      exit 1
    }
  '

# T03: Sourcing path.zsh.inc sets environment and PATH
run_test "T03_path_inc_sourced_success" \
  "Initialization: path.zsh.inc is sourced, updating PATH and environment" \
  '
    local mock_sdk="'$test_dir'/sdk_path"
    mkdir -p "$mock_sdk/bin"
    cat << "EOF" > "$mock_sdk/path.zsh.inc"
export _TEST_GCLOUD_PATH_LOADED="1"
export PATH="${CLOUDSDK_HOME}/bin:${PATH}"
EOF
    cp "'$stub_runner'" "$mock_sdk/bin/gcloud"
    chmod +x "$mock_sdk/bin/gcloud"

    export CLOUDSDK_HOME="$mock_sdk"
    source "'$plugin_file'" || exit 1

    [[ "$_TEST_GCLOUD_PATH_LOADED" == "1" ]] || {
      echo "_TEST_GCLOUD_PATH_LOADED is not 1"
      exit 1
    }
    [[ ":$PATH:" == *":$mock_sdk/bin:"* ]] || {
      echo "PATH does not contain $mock_sdk/bin"
      exit 1
    }
  '

# T04: Missing path.zsh.inc does not cause errors
run_test "T04_path_inc_missing_clean" \
  "Edge-state: missing path.zsh.inc does not produce errors or non-zero status" \
  '
    local mock_sdk="'$test_dir'/sdk_no_path"
    mkdir -p "$mock_sdk"
    # Note: no path.zsh.inc created

    export CLOUDSDK_HOME="$mock_sdk"
    source "'$plugin_file'" || exit 1
  '

# T05: Sourcing completion.zsh.inc defines completion functions
run_test "T05_completion_sourced_success" \
  "Completion: completion.zsh.inc is sourced when present" \
  '
    local mock_sdk="'$test_dir'/sdk_comp"
    mkdir -p "$mock_sdk"
    cat << "EOF" > "$mock_sdk/completion.zsh.inc"
_gcloud() { _values "cmd" "compute" "container" }
export _TEST_GCLOUD_COMPLETION_LOADED="1"
EOF

    export CLOUDSDK_HOME="$mock_sdk"
    source "'$plugin_file'" || exit 1

    [[ "$_TEST_GCLOUD_COMPLETION_LOADED" == "1" ]] || {
      echo "_TEST_GCLOUD_COMPLETION_LOADED is not 1"
      exit 1
    }
    (( $+functions[_gcloud] )) || {
      echo "_gcloud completion function not defined"
      exit 1
    }
  '

# T06: Missing completion file does not fail
run_test "T06_completion_missing_clean" \
  "Edge-state: missing completion file exits cleanly without error" \
  '
    local mock_sdk="'$test_dir'/sdk_no_comp"
    mkdir -p "$mock_sdk"
    # No completion file created

    export CLOUDSDK_HOME="$mock_sdk"
    source "'$plugin_file'" || exit 1
  '

# T07: No SDK found anywhere exits cleanly
run_test "T07_no_sdk_installed_clean" \
  "Edge-state: unconfigured environment without SDK installed completes cleanly" \
  '
    unset CLOUDSDK_HOME
    export HOME="'$test_dir'/empty_home"
    mkdir -p "$HOME"

    source "'$plugin_file'" || exit 1
    [[ -z "$CLOUDSDK_HOME" ]] || {
      echo "Expected CLOUDSDK_HOME to remain unset, got $CLOUDSDK_HOME"
      exit 1
    }
  '

# T08: Argument quoting and space preservation
run_test "T08_argument_quoting_and_execution" \
  "Argument preservation: gcloud forwards multi-word arguments with spaces intact" \
  '
    local mock_sdk="'$test_dir'/sdk_exec"
    mkdir -p "$mock_sdk/bin"
    cat << "EOF" > "$mock_sdk/path.zsh.inc"
export PATH="${CLOUDSDK_HOME}/bin:${PATH}"
EOF
    cp "'$stub_runner'" "$mock_sdk/bin/gcloud"
    chmod +x "$mock_sdk/bin/gcloud"

    local log_file="'$test_dir'/logs/t08_call.json"
    export STUB_CALL_LOG_GCLOUD="$log_file"
    export CLOUDSDK_HOME="$mock_sdk"
    source "'$plugin_file'" || exit 1

    gcloud compute instances list --filter "zone:us-central1* AND status:RUNNING" || exit 1

    [[ -f "$log_file" ]] || { echo "Call log file missing"; exit 1; }

    # Parse and verify arguments using host python
    "'$host_python'" -c "
import json, sys
with open(\"$log_file\") as f:
    data = json.load(f)
args = data.get(\"args\", [])
expected = [\"compute\", \"instances\", \"list\", \"--filter\", \"zone:us-central1* AND status:RUNNING\"]
if args != expected:
    sys.stderr.write(f\"Argument mismatch: expected {expected}, got {args}\n\")
    sys.exit(1)
" || exit 1
  '

# T09: Failure propagation with invalid flag
run_test "T09_failure_propagation" \
  "Failure propagation: gcloud propagates non-zero exit status on error" \
  '
    local mock_sdk="'$test_dir'/sdk_fail"
    mkdir -p "$mock_sdk/bin"
    cat << "EOF" > "$mock_sdk/path.zsh.inc"
export PATH="${CLOUDSDK_HOME}/bin:${PATH}"
EOF
    cp "'$stub_runner'" "$mock_sdk/bin/gcloud"
    chmod +x "$mock_sdk/bin/gcloud"

    export CLOUDSDK_HOME="$mock_sdk"
    source "'$plugin_file'" || exit 1

    gcloud --invalid-flag 2>/dev/null
    rc=$?
    [[ $rc -eq 2 ]] || {
      echo "Expected exit status 2, got $rc"
      exit 1
    }
  '

# T10: PROTECTED CONDITION REGRESSION TEST
# Condition protected: [[ -f "${CLOUDSDK_HOME}/path.zsh.inc" ]] at line 35 of gcloud.plugin.zsh
run_test "T10_REGRESSION_path_inc_condition" \
  "Regression guard: verifies [[ -f \"\${CLOUDSDK_HOME}/path.zsh.inc\" ]] protects SDK PATH initialization" \
  '
    local mock_sdk="'$test_dir'/sdk_regression"
    mkdir -p "$mock_sdk/bin"
    cat << "EOF" > "$mock_sdk/path.zsh.inc"
export _GCLOUD_PATH_INC_ACTIVE="1"
export PATH="${CLOUDSDK_HOME}/bin:${PATH}"
EOF
    cp "'$stub_runner'" "$mock_sdk/bin/gcloud"
    chmod +x "$mock_sdk/bin/gcloud"

    export CLOUDSDK_HOME="$mock_sdk"
    source "'$plugin_file'" || exit 1

    # Protected condition assertion:
    # If the condition [[ -f "${CLOUDSDK_HOME}/path.zsh.inc" ]] is satisfied,
    # path.zsh.inc MUST be sourced.
    if [[ "$_GCLOUD_PATH_INC_ACTIVE" != "1" ]]; then
      echo "REGRESSION: _GCLOUD_PATH_INC_ACTIVE is not 1; path.zsh.inc was not sourced"
      exit 1
    fi

    if [[ ":$PATH:" != *":$mock_sdk/bin:"* ]]; then
      echo "REGRESSION: PATH does not contain $mock_sdk/bin; path.zsh.inc did not update PATH"
      exit 1
    fi

    local gcloud_path=$(command -v gcloud)
    if [[ "$gcloud_path" != "$mock_sdk/bin/gcloud" ]]; then
      echo "REGRESSION: gcloud binary does not resolve to $mock_sdk/bin/gcloud (got: $gcloud_path)"
      exit 1
    fi
  '

# ==============================================================================
# Summary
# ==============================================================================
print -r -- "------------------------------------------------------------"
print -r -- "Results: $passed_tests / $total_tests passed ($failed_tests failed)"
print -r -- "------------------------------------------------------------"

if (( failed_tests > 0 )); then
  exit 1
fi
exit 0
