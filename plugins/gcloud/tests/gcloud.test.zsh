#!/usr/bin/env zsh
# ==============================================================================
# Oh My Zsh - gcloud plugin isolated failure diagnostics test
# Task: R14-T058 (Explain a failing invocation: gcloud)
# ==============================================================================

emulate -LR zsh
setopt aliases

# Resolve plugin path
local plugin_file="${0:A:h:h}/gcloud.plugin.zsh"
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
local host_tools="$test_dir/host_tools"
mkdir -p "$host_tools"
local host_python="${PYTHON_BIN:-${commands[python3]:-$(command -v python3 2>/dev/null)}}"
if [[ -z "$host_python" || ! -x "$host_python" ]]; then
  print -u2 -r -- "FAIL: Python 3 executable not found"
  exit 1
fi

# Build a mock Google Cloud SDK installation fixture
local valid_sdk="$test_dir/mock_sdk"
mkdir -p "$valid_sdk/bin"

# Mock stub gcloud binary
cat << EOF > "$valid_sdk/bin/gcloud"
#!$host_python
import sys, json, os

log_file = os.environ.get("STUB_CALL_LOG")
override_status = os.environ.get("STUB_EXIT_STATUS")

args = sys.argv[1:]
cmd_name = os.path.basename(sys.argv[0])

if log_file:
    data = {
        "command": cmd_name,
        "args": args,
    }
    with open(log_file, "w", encoding="utf-8") as f:
        json.dump(data, f)

if override_status is not None:
    sys.exit(int(override_status))

if "--invalid-flag" in args:
    sys.stderr.write(f"ERROR: (gcloud) unrecognized argument: --invalid-flag\\n")
    sys.exit(2)

if "--version" in args or len(args) == 0:
    sys.stdout.write("Google Cloud SDK 499.0.0\\nalpha 2024.11.15\\nbeta 2024.11.15\\n")
    sys.exit(0)

sys.stdout.write("gcloud command executed successfully\\n")
sys.exit(0)
EOF
chmod +x "$valid_sdk/bin/gcloud"

# Create path.zsh.inc inside mock SDK
cat << EOF > "$valid_sdk/path.zsh.inc"
# path.zsh.inc mock
export PATH="$valid_sdk/bin:\$PATH"
EOF

# Create completion.zsh.inc inside mock SDK
cat << EOF > "$valid_sdk/completion.zsh.inc"
# completion.zsh.inc mock
_gcloud_completion_loaded="true"
compdef() { :; }
EOF

# Assertion helper in Python
cat << EOF > "$test_dir/assert_test.py"
#!$host_python
import sys, json, os

(
    _, test_id, desc, mode, exp_status_str,
    exp_cmd, exp_args_json, actual_status_str,
    call_log_path, err_log_path, out_log_path,
    decoy_intact_str, out_json_file
) = sys.argv[:13]

errors = []
exp_status = int(exp_status_str)
try:
    actual_status = int(actual_status_str)
except ValueError:
    actual_status = -1

exp_args = json.loads(exp_args_json) if exp_args_json != "null" else None

actual_stderr = ""
if os.path.exists(err_log_path):
    with open(err_log_path, "r", encoding="utf-8") as f:
        actual_stderr = f.read()

actual_stdout = ""
if os.path.exists(out_log_path):
    with open(out_log_path, "r", encoding="utf-8") as f:
        actual_stdout = f.read()

actual_call = None
if os.path.exists(call_log_path):
    try:
        with open(call_log_path, "r", encoding="utf-8") as f:
            actual_call = json.load(f)
    except Exception as e:
        errors.append(f"Failed to read call log: {e}")

# Check exit status
if actual_status != exp_status:
    errors.append(f"Exit status mismatch: expected {exp_status}, got {actual_status}")

# Check command & arguments
if exp_cmd != "null":
    if not actual_call:
        errors.append(f"Expected call to {exp_cmd}, but no command was logged")
    else:
        if actual_call.get("command") != exp_cmd:
            errors.append(f"Command mismatch: expected {exp_cmd}, got {actual_call.get('command')}")
        if exp_args is not None:
            if actual_call.get("args") != exp_args:
                errors.append(f"Arguments mismatch: expected {exp_args}, got {actual_call.get('args')}")

# Check failure mode diagnostics
if mode == "failure_diagnostic":
    if "directory not found" not in actual_stdout and "directory not found" not in actual_stderr:
        errors.append("Expected 'directory not found' diagnostic in output")

if mode == "missing_cmd":
    if actual_call is not None:
        errors.append("Expected no command invocation when gcloud binary is missing from PATH")

# Check decoy integrity
if decoy_intact_str != "true":
    errors.append("Decoy file integrity check failed; side-effects outside sandbox detected")

passed = len(errors) == 0

result_data = {
    "test_id": test_id,
    "description": desc,
    "mode": mode,
    "passed": passed,
    "expected_status": exp_status,
    "actual_status": actual_status,
    "expected_command": exp_cmd if exp_cmd != "null" else None,
    "actual_command": actual_call.get("command") if actual_call else None,
    "expected_args": exp_args,
    "actual_args": actual_call.get("args") if actual_call else None,
    "stdout": actual_stdout.strip(),
    "stderr": actual_stderr.strip(),
    "errors": errors
}

if out_json_file and out_json_file != "null":
    with open(out_json_file, "a", encoding="utf-8") as f:
        f.write(json.dumps(result_data) + "\n")

if not passed:
    sys.stderr.write(f"FAIL [{test_id}] {desc}\\n")
    for err in errors:
        sys.stderr.write(f"  - {err}\\n")
    if actual_stderr:
        sys.stderr.write(f"  actual stderr:\\n{actual_stderr}\\n")
    if actual_stdout:
        sys.stderr.write(f"  actual stdout:\\n{actual_stdout}\\n")
    sys.exit(1)
else:
    print(f"PASS [{test_id}] {desc}")
    sys.exit(0)
EOF
chmod +x "$test_dir/assert_test.py"

local record_json="${RECORD_JSON:-}"
local total_tests=0
local passed_tests=0
local failed_tests=0

run_test() {
  local test_id="$1"
  local desc="$2"
  local mode="$3"
  local exp_status="$4"
  local exp_cmd="$5"
  local exp_args_json="$6"
  local setup_cmd="$7"
  local test_script="$8"

  (( total_tests++ ))

  local sandbox="$test_dir/sandbox_$test_id"
  local logs_dir="$test_dir/logs_$test_id"
  mkdir -p "$sandbox" "$logs_dir"

  # Populate sandbox with decoy file
  local decoy_file="$sandbox/decoy_$test_id.txt"
  echo "safe_content" > "$decoy_file"

  local call_log="$logs_dir/call.log"
  local err_log="$logs_dir/err.log"
  local out_log="$logs_dir/out.log"

  # Execute inside an isolated zsh child process
  (
    cd "$sandbox" || exit 1
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export TMPDIR="$test_dir/tmp"
    export STUB_CALL_LOG="$call_log"

    eval "$setup_cmd"
    eval "$test_script"
  ) > "$out_log" 2> "$err_log"
  local actual_status=$?

  # Check decoy preservation
  local decoy_intact="true"
  if [[ ! -f "$decoy_file" ]] || [[ "$(< "$decoy_file")" != "safe_content" ]]; then
    decoy_intact="false"
  fi

  "$test_dir/assert_test.py" \
    "$test_id" \
    "$desc" \
    "$mode" \
    "$exp_status" \
    "$exp_cmd" \
    "$exp_args_json" \
    "$actual_status" \
    "$call_log" \
    "$err_log" \
    "$out_log" \
    "$decoy_intact" \
    "${record_json:-null}"

  if [[ $? -eq 0 ]]; then
    (( passed_tests++ ))
  else
    (( failed_tests++ ))
  fi
}

# ==============================================================================
# Test Cases
# ==============================================================================

# Case 1: Failing invocation - invalid CLOUDSDK_HOME reports diagnostic and returns 1
run_test \
  "T01_failure_invalid_cloudsdk_home" \
  "Failing invocation: invalid CLOUDSDK_HOME reports diagnostic error and returns 1" \
  "failure_diagnostic" \
  1 \
  "null" \
  "null" \
  "export PATH='/usr/bin:/bin'; export CLOUDSDK_HOME='$test_dir/nonexistent/google-cloud-sdk'" \
  "source '$plugin_file'"

# Case 2: Consequent failure - missing gcloud on PATH fails with 127
run_test \
  "T02_consequent_command_failure" \
  "Failing command: gcloud invocation without valid SDK fails with status 127" \
  "missing_cmd" \
  127 \
  "null" \
  "null" \
  "export PATH='/usr/bin:/bin'; export CLOUDSDK_HOME='$test_dir/nonexistent/google-cloud-sdk'; source '$plugin_file' 2>/dev/null || true" \
  "gcloud compute instances list"

# Case 3: Corrected invocation - valid CLOUDSDK_HOME initializes SDK, PATH and completion
run_test \
  "T03_corrected_invocation_success" \
  "Corrected invocation: valid CLOUDSDK_HOME loads path.zsh.inc and completion.zsh.inc" \
  "init_success" \
  0 \
  "null" \
  "null" \
  "export PATH='/usr/bin:/bin'; export CLOUDSDK_HOME='$valid_sdk'" \
  "source '$plugin_file' && [[ \"\$PATH\" == *\"$valid_sdk/bin\"* ]] && [[ \"\$_gcloud_completion_loaded\" == 'true' ]]"

# Case 4: Corrected invocation - gcloud executes successfully after proper initialization
run_test \
  "T04_gcloud_command_execution" \
  "Corrected command: gcloud --version executes with exit status 0" \
  "cmd_exec" \
  0 \
  "gcloud" \
  '["--version"]' \
  "export PATH='/usr/bin:/bin'; export CLOUDSDK_HOME='$valid_sdk'; source '$plugin_file'" \
  "gcloud --version"

# Case 5: Argument forwarding and quoting with multi-word strings
run_test \
  "T05_argument_quoting_with_spaces" \
  "Argument handling: preserves multi-word quoted argument boundaries" \
  "cmd_exec" \
  0 \
  "gcloud" \
  '["compute", "instances", "list", "--project", "production web cluster"]' \
  "export PATH='/usr/bin:/bin'; export CLOUDSDK_HOME='$valid_sdk'; source '$plugin_file'" \
  "gcloud compute instances list --project \"production web cluster\""

# Case 6: Exit status propagation on invalid flag
run_test \
  "T06_failure_invalid_flag" \
  "Failure propagation: invalid flag propagates exit status 2" \
  "cmd_failure" \
  2 \
  "gcloud" \
  '["--invalid-flag"]' \
  "export PATH='/usr/bin:/bin'; export CLOUDSDK_HOME='$valid_sdk'; source '$plugin_file'" \
  "gcloud --invalid-flag"

# Case 7: Clean exit when CLOUDSDK_HOME is unset and no SDK installed
run_test \
  "T07_missing_sdk_clean_exit" \
  "Unset CLOUDSDK_HOME: exits cleanly without error when SDK not in search locations" \
  "init_clean" \
  0 \
  "null" \
  "null" \
  "export PATH='/usr/bin:/bin'; unset CLOUDSDK_HOME; export HOME='$test_dir/empty_home'" \
  "source '$plugin_file' && [[ -z \"\$CLOUDSDK_HOME\" ]]"

print -- "------------------------------------------------------------"
print -- "Results: $passed_tests / $total_tests passed ($failed_tests failed)"
print -- "------------------------------------------------------------"

if (( failed_tests > 0 || total_tests == 0 )); then
  exit 1
fi

exit 0
