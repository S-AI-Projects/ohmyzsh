#!/usr/bin/env zsh
# ==============================================================================
# Oh My Zsh - kubectl plugin isolated characterization test
# Task: R14-T056 (Clarify one source responsibility: kubectl)
# ==============================================================================

emulate -LR zsh
setopt aliases

# Resolve plugin path
local plugin_file="${0:A:h:h}/kubectl.plugin.zsh"
if [[ ! -f "$plugin_file" ]]; then
  print -u2 -r -- "FAIL: Cannot find kubectl.plugin.zsh at $plugin_file"
  exit 1
fi

local test_dir=$(mktemp -d) || exit 1
trap 'command rm -rf -- "$test_dir"' EXIT INT TERM

# Ensure environment isolation
export ZDOTDIR="$test_dir/zdotdir"
export HOME="$test_dir/home"
export TMPDIR="$test_dir/tmp"
export ZSH="${ZSH:-${0:A:h:h:h:h}}"
export ZSH_CACHE_DIR="$test_dir/cache"
mkdir -p "$ZDOTDIR" "$HOME" "$TMPDIR" "$ZSH_CACHE_DIR/completions" "$test_dir/logs"

# Host Python resolution (absolute path to avoid PATH recursion)
local host_tools="$test_dir/host_tools"
mkdir -p "$host_tools"
local host_python="${PYTHON_BIN:-${commands[python3]:-$(command -v python3 2>/dev/null)}}"
if [[ -z "$host_python" || ! -x "$host_python" ]]; then
  print -u2 -r -- "FAIL: Python 3 executable not found"
  exit 1
fi

# Isolated bin directory with stub
local bin_dir="$test_dir/bin"
mkdir -p "$bin_dir"

# Mock stub executable using absolute host python
cat << EOF > "$test_dir/mock_kubectl"
#!$host_python
import sys, json, os

log_file = os.environ.get("STUB_CALL_LOG")
override_status = os.environ.get("STUB_EXIT_STATUS")

args = sys.argv[1:]
cmd_name = os.path.basename(sys.argv[0])

# Ignore background completion generation calls
if args and args[0] == "completion":
    sys.stdout.write("#compdef kubectl\n")
    sys.exit(0)

if log_file:
    data = {
        "command": cmd_name,
        "args": args,
    }
    with open(log_file, "w", encoding="utf-8") as f:
        json.dump(data, f)

if "STUB_STDOUT" in os.environ:
    sys.stdout.write(os.environ["STUB_STDOUT"])
if "STUB_STDERR" in os.environ:
    sys.stderr.write(os.environ["STUB_STDERR"])

if override_status is not None:
    sys.exit(int(override_status))

if "--invalid-flag" in args:
    sys.stderr.write(f"Error: unknown flag: --invalid-flag\n")
    sys.exit(2)

sys.exit(0)
EOF
chmod +x "$test_dir/mock_kubectl"
ln -sf "$test_dir/mock_kubectl" "$bin_dir/kubectl"

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
            # Special check for kres where timestamp is dynamic
            if mode == "kres_exec":
                act_args = actual_call.get("args", [])
                if len(act_args) < len(exp_args):
                    errors.append(f"Arguments length mismatch: expected at least {len(exp_args)}, got {len(act_args)}")
                else:
                    for i in range(len(exp_args)):
                        if act_args[i] != exp_args[i]:
                            errors.append(f"Argument mismatch at index {i}: expected {exp_args[i]}, got {act_args[i]}")
                    if not any(a.startswith("REFRESHED_AT=") for a in act_args):
                        errors.append("Expected REFRESHED_AT=... in arguments")
            else:
                if actual_call.get("args") != exp_args:
                    errors.append(f"Arguments mismatch: expected {exp_args}, got {actual_call.get('args')}")

# Check missing dependency branch specifics
if mode == "missing_dep":
    if actual_call is not None:
        errors.append("Expected no command invocation when kubectl is missing")

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
    sys.stderr.write(f"FAIL [{test_id}] {desc}\n")
    for err in errors:
        sys.stderr.write(f"  - {err}\n")
    if actual_stderr:
        sys.stderr.write(f"  actual stderr:\n{actual_stderr}\n")
    if actual_stdout:
        sys.stderr.write(f"  actual stdout:\n{actual_stdout}\n")
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

  # Populate sandbox with decoy files to assert file isolation
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
    export ZSH_CACHE_DIR="$test_dir/cache"

    eval "$setup_cmd"

    # Set log file only when running test command to avoid capturing completion
    export STUB_CALL_LOG="$call_log"

    # Run the test snippet
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

# Common setup: isolate PATH with stub kubectl, stub compdef, and source plugin
local default_setup="export PATH='$bin_dir:/usr/bin:/bin'; compdef() { :; }; source '$plugin_file'"

# ==============================================================================
# Characterization Test Cases
# ==============================================================================

# Case 1: Missing dependency - kubectl absent from PATH
run_test \
  "T01_missing_dependency" \
  "Missing dependency: kubectl not in PATH, plugin exits cleanly" \
  "missing_dep" \
  0 \
  "null" \
  "null" \
  "export PATH='/usr/bin:/bin'" \
  "source '$plugin_file'; which kca >/dev/null 2>&1 && exit 42 || exit 0"

# Case 2: Entry point 'kca' without arguments
run_test \
  "T02_kca_no_args" \
  "Entry point kca: expands to 'kubectl --all-namespaces'" \
  "cmd_exec" \
  0 \
  "kubectl" \
  '["--all-namespaces"]' \
  "$default_setup" \
  "kca"

# Case 3: Entry point 'kca' with command and resource
run_test \
  "T03_kca_get_pods" \
  "Entry point kca: forwards command and appends '--all-namespaces'" \
  "cmd_exec" \
  0 \
  "kubectl" \
  '["get", "pods", "--all-namespaces"]' \
  "$default_setup" \
  "kca get pods"

# Case 4: Entry point 'kca' with flags
run_test \
  "T04_kca_with_options" \
  "Entry point kca: forwards options 'get pods -o wide --all-namespaces'" \
  "cmd_exec" \
  0 \
  "kubectl" \
  '["get", "pods", "-o", "wide", "--all-namespaces"]' \
  "$default_setup" \
  "kca get pods -o wide"

# Case 5: Entry point 'kca' with multi-word quoted argument containing spaces
run_test \
  "T05_kca_quoted_with_spaces" \
  "Entry point kca: preserves quoted selector containing spaces" \
  "cmd_exec" \
  0 \
  "kubectl" \
  '["get", "pods", "-l", "app=web frontend", "--all-namespaces"]' \
  "$default_setup" \
  "kca get pods -l \"app=web frontend\""

# Case 6: Entry point 'kaf' basic manifest
run_test \
  "T06_entry_kaf_basic" \
  "Entry point kaf: expands to 'kubectl apply -f manifest.yaml'" \
  "alias_exec" \
  0 \
  "kubectl" \
  '["apply", "-f", "manifest.yaml"]' \
  "$default_setup" \
  "kaf manifest.yaml"

# Case 7: Entry point 'kaf' with spaces in filename
run_test \
  "T07_entry_kaf_quoted_with_spaces" \
  "Entry point kaf: preserves quoted path with spaces" \
  "alias_exec" \
  0 \
  "kubectl" \
  '["apply", "-f", "deployments/web app.yaml"]' \
  "$default_setup" \
  "kaf \"deployments/web app.yaml\""

# Case 8: Entry point 'kapk' basic kustomization directory
run_test \
  "T08_entry_kapk_basic" \
  "Entry point kapk: expands to 'kubectl apply -k ./kustomize'" \
  "alias_exec" \
  0 \
  "kubectl" \
  '["apply", "-k", "./kustomize"]' \
  "$default_setup" \
  "kapk ./kustomize"

# Case 9: Entry point 'kapk' with spaces in directory path
run_test \
  "T09_entry_kapk_quoted_with_spaces" \
  "Entry point kapk: preserves quoted kustomize directory with spaces" \
  "alias_exec" \
  0 \
  "kubectl" \
  '["apply", "-k", "environments/staging cluster"]' \
  "$default_setup" \
  "kapk \"environments/staging cluster\""

# Case 10: Exit status propagation on invalid option
run_test \
  "T10_failure_invalid_option" \
  "Failure propagation: kca with invalid option propagates exit status 2" \
  "cmd_failure" \
  2 \
  "kubectl" \
  '["--invalid-flag", "--all-namespaces"]' \
  "$default_setup" \
  "kca --invalid-flag"

# Case 11: Helper 'kres' at line 113 with arguments
run_test \
  "T11_kres_quoted_args" \
  "Helper kres (line 113): preserves quoted arguments in 'kubectl set env'" \
  "kres_exec" \
  0 \
  "kubectl" \
  '["set", "env", "deployment/web", "--namespace", "production app"]' \
  "$default_setup" \
  "kres deployment/web --namespace \"production app\""

print -- "------------------------------------------------------------"
print -- "Results: $passed_tests / $total_tests passed ($failed_tests failed)"
print -- "------------------------------------------------------------"

if (( failed_tests > 0 || total_tests == 0 )); then
  exit 1
fi

exit 0
