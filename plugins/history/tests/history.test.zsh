#!/usr/bin/env zsh
# ==============================================================================
# Oh My Zsh - history plugin isolated fixture test
# Task: R14-T059 (Integrate a focused check: history)
# ==============================================================================

emulate -LR zsh
setopt aliases

# Resolve plugin path
local plugin_file="${0:A:h:h}/history.plugin.zsh"
if [[ ! -f "$plugin_file" ]]; then
  print -u2 -r -- "FAIL: Cannot find history.plugin.zsh at $plugin_file"
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

# Isolated bin directory with stubs
local bin_dir="$test_dir/bin"
mkdir -p "$bin_dir"

# Mock stub executable using absolute host python
cat << EOF > "$test_dir/mock_stub"
#!$host_python
import sys, json, os

cmd_name = os.path.basename(sys.argv[0])
args = sys.argv[1:]

log_file = os.environ.get(f"STUB_CALL_LOG_{cmd_name.upper()}")
if log_file:
    data = {"command": cmd_name, "args": args}
    with open(log_file, "w", encoding="utf-8") as f:
        json.dump(data, f)

if "--invalid-flag" in args:
    sys.stderr.write(f"{cmd_name}: unrecognized option '--invalid-flag'\\n")
    sys.exit(2)

if cmd_name == "history":
    canned = (
        "    1  git status\\n"
        "    2  git commit -m \\"initial commit\\"\\n"
        "    3  docker compose up -d\\n"
        "    4  pytest tests/test_app.py\\n"
        "    5  grep -rn \\"TODO\\" src/\\n"
    )
    sys.stdout.write(canned)
    sys.exit(0)

elif cmd_name == "less":
    content = sys.stdin.read()
    pager_out = os.environ.get("CAPTURE_PAGER")
    if pager_out:
        with open(pager_out, "w", encoding="utf-8") as pf:
            pf.write(content)
    sys.stdout.write(content)
    sys.exit(0)

elif cmd_name == "grep":
    ignore_case = "-i" in args
    pattern = None
    for a in reversed(args):
        if not a.startswith("-"):
            pattern = a
            break
    content = sys.stdin.read()
    if not pattern:
        sys.stderr.write("grep: missing pattern\\n")
        sys.exit(2)
    lines = content.splitlines()
    matches = []
    p = pattern.lower() if ignore_case else pattern
    for line in lines:
        l = line.lower() if ignore_case else line
        if p in l:
            matches.append(line)
    if matches:
        sys.stdout.write("\\n".join(matches) + "\\n")
        sys.exit(0)
    else:
        sys.exit(1)

sys.exit(0)
EOF
chmod +x "$test_dir/mock_stub"

ln -sf "$test_dir/mock_stub" "$bin_dir/history"
ln -sf "$test_dir/mock_stub" "$bin_dir/less"
ln -sf "$test_dir/mock_stub" "$bin_dir/grep"

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
if call_log_path and call_log_path != "null" and os.path.exists(call_log_path):
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

# Mode specific assertions
if mode == "hs_match":
    if "initial commit" not in actual_stdout:
        errors.append("Expected matching line in hs stdout")

if mode == "hl_pager":
    pager_file = os.environ.get("CAPTURE_PAGER_TEST")
    if pager_file and os.path.exists(pager_file):
        with open(pager_file, "r", encoding="utf-8") as pf:
            pager_content = pf.read()
        if "git status" not in pager_content:
            errors.append("Expected history output to reach pager via pipeline")

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
        f.write(json.dumps(result_data) + "\\n")

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

  local call_log_history="$logs_dir/call_history.log"
  local call_log_less="$logs_dir/call_less.log"
  local call_log_grep="$logs_dir/call_grep.log"
  local err_log="$logs_dir/err.log"
  local out_log="$logs_dir/out.log"

  # Execute inside an isolated zsh child process
  (
    cd "$sandbox" || exit 1
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export TMPDIR="$test_dir/tmp"
    export STUB_CALL_LOG_HISTORY="$call_log_history"
    export STUB_CALL_LOG_LESS="$call_log_less"
    export STUB_CALL_LOG_GREP="$call_log_grep"

    eval "$setup_cmd"
    eval "$test_script"
  ) > "$out_log" 2> "$err_log"
  local actual_status=$?

  # Check decoy preservation
  local decoy_intact="true"
  if [[ ! -f "$decoy_file" ]] || [[ "$(< "$decoy_file")" != "safe_content" ]]; then
    decoy_intact="false"
  fi

  local target_log="null"
  if [[ "$exp_cmd" == "history" ]]; then
    target_log="$call_log_history"
  elif [[ "$exp_cmd" == "less" ]]; then
    target_log="$call_log_less"
  elif [[ "$exp_cmd" == "grep" ]]; then
    target_log="$call_log_grep"
  fi

  "$test_dir/assert_test.py" \
    "$test_id" \
    "$desc" \
    "$mode" \
    "$exp_status" \
    "$exp_cmd" \
    "$exp_args_json" \
    "$actual_status" \
    "$target_log" \
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

local default_setup="export PATH='$bin_dir:/usr/bin:/bin'; disable history; source '$plugin_file'"

# ==============================================================================
# Test Cases
# ==============================================================================

# Case 1: Alias availability after plugin initialization
run_test \
  "T01_alias_availability" \
  "Initialization: aliases h, hl, hs, hsi are defined after sourcing" \
  "alias_check" \
  0 \
  "null" \
  "null" \
  "export PATH='$bin_dir:/usr/bin:/bin'; source '$plugin_file'" \
  "[[ -n \"\${aliases[h]}\" && -n \"\${aliases[hl]}\" && -n \"\${aliases[hs]}\" && -n \"\${aliases[hsi]}\" ]]"

# Case 2: Entry point 'h' invokes history successfully
run_test \
  "T02_entry_h_success" \
  "Entry point h: invokes history command and exits with 0" \
  "h_exec" \
  0 \
  "history" \
  '[]' \
  "$default_setup" \
  "h"

# Case 3: Failure propagation for 'h' on invalid argument
run_test \
  "T03_entry_h_failure_invalid_flag" \
  "Failure propagation: h with invalid flag propagates exit status 2" \
  "h_fail" \
  2 \
  "history" \
  '["--invalid-flag"]' \
  "$default_setup" \
  "h --invalid-flag"

# Case 4: Entry point 'hl' executes pipeline history | less with stub pager
run_test \
  "T04_entry_hl_success" \
  "Entry point hl: pipes history output to less pager" \
  "hl_pager" \
  0 \
  "less" \
  '[]' \
  "$default_setup; export CAPTURE_PAGER='$test_dir/pager_capture.txt'; export CAPTURE_PAGER_TEST='$test_dir/pager_capture.txt'" \
  "hl"

# Case 5: Failure propagation for 'hl' on pager failure
run_test \
  "T05_entry_hl_failure_pager" \
  "Failure propagation: hl with invalid pager flag propagates exit status 2" \
  "hl_fail" \
  2 \
  "less" \
  '["--invalid-flag"]' \
  "$default_setup" \
  "hl --invalid-flag"

# Case 6: Entry point 'hs' with matching search argument
run_test \
  "T06_entry_hs_match_success" \
  "Entry point hs: pipes history to grep and returns matching line" \
  "hs_match" \
  0 \
  "grep" \
  '["git commit"]' \
  "$default_setup" \
  "hs \"git commit\""

# Case 7: Entry point 'hs' with non-matching search argument exits 1
run_test \
  "T07_entry_hs_no_match" \
  "Entry point hs: non-matching search exits with status 1" \
  "hs_nomatch" \
  1 \
  "grep" \
  '["nonexistent_pattern"]' \
  "$default_setup" \
  "hs \"nonexistent_pattern\""

# Case 8: Quoting and multi-word argument boundary preservation in 'hs'
run_test \
  "T08_entry_hs_quoted_with_spaces" \
  "Argument preservation: hs preserves multi-word search string intact" \
  "cmd_exec" \
  0 \
  "grep" \
  '["docker compose up -d"]' \
  "$default_setup" \
  "hs \"docker compose up -d\""

# Case 9: Failure propagation for 'hs' on invalid flag
run_test \
  "T09_entry_hs_failure_invalid_flag" \
  "Failure propagation: hs with invalid flag propagates exit status 2" \
  "hs_fail" \
  2 \
  "grep" \
  '["--invalid-flag"]' \
  "$default_setup" \
  "hs --invalid-flag"

# Case 10: State cleanup verification - ensure temporary files cleaned up
run_test \
  "T10_state_cleanup_verification" \
  "Cleanup verification: temporary directory and decoy state preserved" \
  "cleanup" \
  0 \
  "null" \
  "null" \
  "$default_setup" \
  "[[ -d '$test_dir' && -f 'decoy_T10_state_cleanup_verification.txt' ]]"

print -- "------------------------------------------------------------"
print -- "Results: $passed_tests / $total_tests passed ($failed_tests failed)"
print -- "------------------------------------------------------------"

if (( failed_tests > 0 || total_tests == 0 )); then
  exit 1
fi

exit 0
