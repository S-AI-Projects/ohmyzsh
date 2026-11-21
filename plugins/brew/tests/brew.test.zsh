#!/usr/bin/env zsh
# ==============================================================================
# Oh My Zsh - brew plugin isolated fixture test
# Task: R14-T055 (Isolate environment dependencies: brew)
# ==============================================================================

emulate -LR zsh
setopt aliases

# Resolve plugin path
local plugin_file="${0:A:h:h}/brew.plugin.zsh"
if [[ ! -f "$plugin_file" ]]; then
  print -u2 -r -- "FAIL: Cannot find brew.plugin.zsh at $plugin_file"
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

# Isolated bin directories with stubs
local bin_dir="$test_dir/bin"
local custom_bin="$test_dir/custom_bin"
mkdir -p "$bin_dir" "$custom_bin"

# Mock stub executable using absolute host python
cat << EOF > "$test_dir/mock_brew"
#!$host_python
import sys, json, os

log_file = os.environ.get("STUB_CALL_LOG")
override_status = os.environ.get("STUB_EXIT_STATUS")
stub_prefix = os.environ.get("MOCK_HOMEBREW_PREFIX", "/mock/homebrew")

args = sys.argv[1:]
cmd_name = os.path.basename(sys.argv[0])

if log_file:
    data = {
        "command": cmd_name,
        "args": args,
    }
    with open(log_file, "w", encoding="utf-8") as f:
        json.dump(data, f)

if "STUB_STDOUT" in os.environ:
    sys.stdout.write(os.environ["STUB_STDOUT"])
elif len(args) == 1 and args[0] == "shellenv":
    sys.stdout.write(f'export HOMEBREW_PREFIX="{stub_prefix}"\nexport PATH="{stub_prefix}/bin:\$PATH"\n')
elif len(args) == 1 and args[0] == "--prefix":
    sys.stdout.write(f"{stub_prefix}\n")

if "STUB_STDERR" in os.environ:
    sys.stderr.write(os.environ["STUB_STDERR"])

if override_status is not None:
    sys.exit(int(override_status))

if "--invalid-flag" in args:
    sys.stderr.write(f"{cmd_name}: invalid option: --invalid-flag\n")
    sys.exit(2)

sys.exit(0)
EOF
chmod +x "$test_dir/mock_brew"

# Create symlinks named 'brew'
ln -sf "$test_dir/mock_brew" "$bin_dir/brew"
ln -sf "$test_dir/mock_brew" "$custom_bin/brew"

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

# Check missing dependency branch specifics
if mode == "missing_dep_silent":
    if actual_call is not None:
        errors.append("Expected no command invocation when brew is missing")
elif mode == "missing_dep_invalid_location":
    if "is not executable" not in actual_stdout and "is not executable" not in actual_stderr:
        errors.append("Expected 'is not executable' error message in output")
    if actual_call is not None:
        errors.append("Expected no command invocation for non-executable BREW_LOCATION")

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
    export STUB_CALL_LOG="$call_log"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export TMPDIR="$test_dir/tmp"

    eval "$setup_cmd"

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

# ==============================================================================
# Test Cases
# ==============================================================================

# Case 1: Missing dependency - brew not in PATH, ZSH_BREW_LOCATIONS=(), plugin exits cleanly
run_test \
  "T01_missing_dep_silent" \
  "Missing dependency: brew not in PATH and locations disabled, plugin exits cleanly" \
  "missing_dep_silent" \
  0 \
  "null" \
  "null" \
  "export PATH='/usr/bin:/bin'; ZSH_BREW_LOCATIONS=(); unset BREW_LOCATION HOMEBREW_PREFIX" \
  "source '$plugin_file'; which ba >/dev/null 2>&1 && exit 42 || exit 0"

# Case 2: Missing dependency - BREW_LOCATION points to non-executable path
run_test \
  "T02_missing_dep_invalid_location" \
  "Missing dependency: BREW_LOCATION is not executable, reports error" \
  "missing_dep_invalid_location" \
  0 \
  "null" \
  "null" \
  "export PATH='/usr/bin:/bin'; export BREW_LOCATION='$test_dir/nonexistent/brew'; unset HOMEBREW_PREFIX" \
  "source '$plugin_file'; which ba >/dev/null 2>&1 && exit 42 || exit 0"

# Case 3: Custom BREW_LOCATION points to valid executable stub
run_test \
  "T03_custom_brew_location_success" \
  "Custom BREW_LOCATION: valid executable evaluated via shellenv" \
  "exec_success" \
  0 \
  "brew" \
  '["shellenv"]' \
  "export PATH='/usr/bin:/bin'; export BREW_LOCATION='$custom_bin/brew'; unset HOMEBREW_PREFIX" \
  "source '$plugin_file' && [[ -n \"\$HOMEBREW_PREFIX\" ]] && which ba >/dev/null 2>&1"

# Case 4: Entry point 'ba' without arguments -> brew autoremove
run_test \
  "T04_entry_ba_basic" \
  "Entry point ba: expands to 'brew autoremove'" \
  "alias_exec" \
  0 \
  "brew" \
  '["autoremove"]' \
  "export PATH='$bin_dir:/usr/bin:/bin'; export HOMEBREW_PREFIX='/mock/homebrew'; source '$plugin_file'" \
  "ba"

# Case 5: Entry point 'ba' with flags -> brew autoremove --dry-run
run_test \
  "T05_entry_ba_with_flags" \
  "Entry point ba: preserves flags '--dry-run'" \
  "alias_exec" \
  0 \
  "brew" \
  '["autoremove", "--dry-run"]' \
  "export PATH='$bin_dir:/usr/bin:/bin'; export HOMEBREW_PREFIX='/mock/homebrew'; source '$plugin_file'" \
  "ba --dry-run"

# Case 6: Entry point 'bcfg' -> brew config
run_test \
  "T06_entry_bcfg_basic" \
  "Entry point bcfg: expands to 'brew config'" \
  "alias_exec" \
  0 \
  "brew" \
  '["config"]' \
  "export PATH='$bin_dir:/usr/bin:/bin'; export HOMEBREW_PREFIX='/mock/homebrew'; source '$plugin_file'" \
  "bcfg"

# Case 7: Entry point 'bci' -> brew info --cask <cask>
run_test \
  "T07_entry_bci_single_cask" \
  "Entry point bci: expands to 'brew info --cask <cask>'" \
  "alias_exec" \
  0 \
  "brew" \
  '["info", "--cask", "google-chrome"]' \
  "export PATH='$bin_dir:/usr/bin:/bin'; export HOMEBREW_PREFIX='/mock/homebrew'; source '$plugin_file'" \
  "bci google-chrome"

# Case 8: Entry point 'bci' -> preserve quoted arguments with spaces
run_test \
  "T08_entry_bci_quoted_with_spaces" \
  "Entry point bci: preserves quoted arguments with spaces" \
  "alias_exec" \
  0 \
  "brew" \
  '["info", "--cask", "visual studio code"]' \
  "export PATH='$bin_dir:/usr/bin:/bin'; export HOMEBREW_PREFIX='/mock/homebrew'; source '$plugin_file'" \
  "bci \"visual studio code\""

# Case 9: Exit status propagation on invalid option
run_test \
  "T09_failure_invalid_option" \
  "Failure propagation: bcfg with invalid option propagates exit status 2" \
  "alias_failure" \
  2 \
  "brew" \
  '["config", "--invalid-flag"]' \
  "export PATH='$bin_dir:/usr/bin:/bin'; export HOMEBREW_PREFIX='/mock/homebrew'; source '$plugin_file'" \
  "bcfg --invalid-flag"

# Case 10: Environment isolation and sbin PATH addition
run_test \
  "T10_environment_sbin_setup" \
  "Environment configuration: adds \$HOMEBREW_PREFIX/sbin to PATH" \
  "env_setup" \
  0 \
  "brew" \
  '["--prefix"]' \
  "export PATH='$bin_dir:/usr/bin:/bin'; unset HOMEBREW_PREFIX; export MOCK_HOMEBREW_PREFIX='$test_dir/mock_homebrew'; mkdir -p '$test_dir/mock_homebrew/sbin'" \
  "source '$plugin_file' && [[ \"\$PATH\" == *\"$test_dir/mock_homebrew/sbin\"* ]]"

print -- "------------------------------------------------------------"
print -- "Results: $passed_tests / $total_tests passed ($failed_tests failed)"
print -- "------------------------------------------------------------"

if (( failed_tests > 0 || total_tests == 0 )); then
  exit 1
fi

exit 0
