#!/usr/bin/env zsh
# ==============================================================================
# Oh My Zsh - autopep8 plugin isolated characterization test
# Task: R14-T057 (Publish a tested usage example: autopep8)
# ==============================================================================

emulate -LR zsh
setopt aliases

# Resolve plugin directory
local plugin_dir="${0:A:h:h}"
local completion_file="$plugin_dir/_autopep8"
if [[ ! -f "$completion_file" ]]; then
  print -u2 -r -- "FAIL: Cannot find _autopep8 at $completion_file"
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

# Isolated bin directory with stub
local bin_dir="$test_dir/bin"
mkdir -p "$bin_dir"

# Mock autopep8 stub executable using absolute host python
cat << EOF > "$test_dir/mock_autopep8"
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
    sys.stderr.write(f"autopep8: error: unrecognized arguments: --invalid-flag\n")
    sys.exit(2)

# Check for non-existent file
for a in args:
    if a.startswith("nonexistent"):
        sys.stderr.write(f"[Errno 2] No such file or directory: '{a}'\n")
        sys.exit(1)

# Handle --diff mode
if "--diff" in args:
    target = None
    for a in args:
        if not a.startswith("-"):
            target = a
            break
    if target and os.path.exists(target):
        with open(target, "r", encoding="utf-8") as tf:
            content = tf.read()
        if "clean" in target or "# clean" in content:
            # File already conforms to PEP 8; no diff output
            sys.exit(0)
    # Output unified diff as documented
    sys.stdout.write(
        "--- original/example.py\\n"
        "+++ fixed/example.py\\n"
        "@@ -1,2 +1,2 @@\\n"
        "-def foo( x ):\\n"
        "-    return x+1\\n"
        "+def foo(x):\\n"
        "+    return x + 1\\n"
    )
    sys.exit(0)

# Handle --in-place mode
if "--in-place" in args:
    for a in args:
        if not a.startswith("-") and os.path.exists(a):
            with open(a, "w", encoding="utf-8") as tf:
                tf.write("def foo(x):\\n    return x + 1\\n")
    sys.exit(0)

if "STUB_STDOUT" in os.environ:
    sys.stdout.write(os.environ["STUB_STDOUT"])
if "STUB_STDERR" in os.environ:
    sys.stderr.write(os.environ["STUB_STDERR"])

sys.exit(0)
EOF
chmod +x "$test_dir/mock_autopep8"
ln -sf "$test_dir/mock_autopep8" "$bin_dir/autopep8"

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

# Check diff output for documented example
if mode == "diff_example":
    if "--- original/example.py" not in actual_stdout or "+++ fixed/example.py" not in actual_stdout:
        errors.append("Expected unified diff output in stdout for documented diff example")

if mode == "diff_clean":
    if actual_stdout.strip() != "":
        errors.append(f"Expected empty diff output for clean file, got: {actual_stdout.strip()}")

# Check missing dependency
if mode == "missing_dep":
    if actual_call is not None:
        errors.append("Expected no command invocation when autopep8 is missing")

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

local default_setup="export PATH='$bin_dir:/usr/bin:/bin'"

# ==============================================================================
# Test Cases
# ==============================================================================

# Case 1: Plugin initialization and completion registration in compinit
run_test \
  "T01_init_completion_registration" \
  "Plugin initialization: registers completion definition in compinit" \
  "init_comp" \
  0 \
  "null" \
  "null" \
  "export PATH='/usr/bin:/bin'" \
  "fpath=('$plugin_dir' \$fpath); autoload -Uz compinit; compinit -d '$test_dir/zcompdump'; [[ \"\$_comps[autopep8]\" == '_autopep8' ]]"

# Case 2: Missing dependency - autopep8 binary not found on PATH
run_test \
  "T02_missing_dependency" \
  "Missing dependency: autopep8 not found in PATH fails with 127" \
  "missing_dep" \
  127 \
  "null" \
  "null" \
  "export PATH='/usr/bin:/bin'" \
  "autopep8 --version"

# Case 3: Documented usage example - preview diff
run_test \
  "T03_documented_diff_example" \
  "Documented command: 'autopep8 --diff example.py' previews formatting diff" \
  "diff_example" \
  0 \
  "autopep8" \
  '["--diff", "example.py"]' \
  "$default_setup; echo 'def foo( x ):\n    return x+1' > example.py" \
  "autopep8 --diff example.py"

# Case 4: Documented usage example - in-place aggressive formatting
run_test \
  "T04_documented_in_place_example" \
  "Documented command: 'autopep8 --in-place --aggressive example.py' formats file" \
  "cmd_exec" \
  0 \
  "autopep8" \
  '["--in-place", "--aggressive", "example.py"]' \
  "$default_setup; echo 'def foo( x ):\n    return x+1' > example.py" \
  "autopep8 --in-place --aggressive example.py && grep -q 'def foo(x):' example.py"

# Case 5: Documented state verification - clean file diff produces no changes
run_test \
  "T05_documented_state_verification" \
  "Documented verification: diff on formatted file outputs nothing and exits 0" \
  "diff_clean" \
  0 \
  "autopep8" \
  '["--diff", "clean_example.py"]' \
  "$default_setup; echo 'def foo(x):\n    return x + 1\n# clean' > clean_example.py" \
  "autopep8 --diff clean_example.py"

# Case 6: Argument boundary and quoting preservation with spaces in path
run_test \
  "T06_quoted_path_with_spaces" \
  "Argument preservation: preserves paths containing spaces" \
  "cmd_exec" \
  0 \
  "autopep8" \
  '["--in-place", "source code/my module.py"]' \
  "$default_setup; mkdir -p 'source code'; echo 'def foo( x ):\n    return x+1' > 'source code/my module.py'" \
  "autopep8 --in-place \"source code/my module.py\""

# Case 7: Failure edge state - invalid option propagates exit status 2
run_test \
  "T07_failure_invalid_option" \
  "Failure propagation: invalid option propagates exit status 2" \
  "cmd_failure" \
  2 \
  "autopep8" \
  '["--invalid-flag", "example.py"]' \
  "$default_setup; touch example.py" \
  "autopep8 --invalid-flag example.py"

# Case 8: Failure edge state - non-existent file propagates exit status 1
run_test \
  "T08_failure_nonexistent_file" \
  "Failure propagation: non-existent file propagates exit status 1" \
  "cmd_failure" \
  1 \
  "autopep8" \
  '["nonexistent_script.py"]' \
  "$default_setup" \
  "autopep8 nonexistent_script.py"

print -- "------------------------------------------------------------"
print -- "Results: $passed_tests / $total_tests passed ($failed_tests failed)"
print -- "------------------------------------------------------------"

if (( failed_tests > 0 || total_tests == 0 )); then
  exit 1
fi

exit 0
