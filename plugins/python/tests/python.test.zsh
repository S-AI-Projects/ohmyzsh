#!/usr/bin/env zsh

emulate -LR zsh
setopt aliases

# Resolve plugin path
local plugin_file="${0:A:h:h}/python.plugin.zsh"
if [[ ! -f "$plugin_file" ]]; then
  print -u2 -r -- "FAIL: Cannot find python.plugin.zsh at $plugin_file"
  exit 1
fi

local test_dir=$(mktemp -d) || exit 1
trap 'command rm -rf -- "$test_dir"' EXIT INT TERM

# Ensure isolation
export ZDOTDIR="$test_dir/zdotdir"
export HOME="$test_dir/home"
export TMPDIR="$test_dir/tmp"
export ZSH="${ZSH:-${0:A:h:h:h:h}}"
mkdir -p "$ZDOTDIR" "$HOME" "$TMPDIR" "$test_dir/logs"

# Host Python
local host_tools="$test_dir/host_tools"
mkdir -p "$host_tools"
local host_python="${PYTHON_BIN:-${commands[python3]:-$(command -v python3 2>/dev/null)}}"
if [[ -n "$host_python" && -x "$host_python" ]]; then
  ln -sf "$host_python" "$host_tools/python3"
  ln -sf "$host_python" "$host_tools/python"
fi

# Isolated bin directory with stubs
local bin_dir="$test_dir/bin"
mkdir -p "$bin_dir"

# Mock stub executable using absolute host python to avoid env PATH recursion
cat << EOF > "$test_dir/mock_stub"
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

if "STUB_STDOUT" in os.environ:
    sys.stdout.write(os.environ["STUB_STDOUT"])
if "STUB_STDERR" in os.environ:
    sys.stderr.write(os.environ["STUB_STDERR"])

if override_status is not None:
    sys.exit(int(override_status))

if "--invalid-flag" in args:
    sys.stderr.write(f"{cmd_name}: unrecognized option '--invalid-flag'\n")
    sys.exit(2)

sys.exit(0)
EOF
chmod +x "$test_dir/mock_stub"

ln -s "$test_dir/mock_stub" "$bin_dir/find"
ln -s "$test_dir/mock_stub" "$bin_dir/grep"
ln -s "$test_dir/mock_stub" "$bin_dir/python3"
ln -s "$test_dir/mock_stub" "$bin_dir/which"

# Assertion helper
cat << EOF > "$test_dir/assert_quoting.py"
#!$host_python
import sys, json, os

(
    _, test_id, desc, mode, alias_name, exp_status_str,
    exp_cmd, exp_args_json, actual_status_str,
    call_log_path, err_log_path, decoy_intact_str, out_json_file
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

actual_cmd = ""
actual_args = []
if exp_cmd != "null":
    if not os.path.exists(call_log_path):
        errors.append("call log not generated: command was not invoked")
    else:
        with open(call_log_path, "r", encoding="utf-8") as f:
            call_data = json.load(f)
            actual_cmd = call_data.get("command", "")
            actual_args = call_data.get("args", [])
        if actual_cmd != exp_cmd:
            errors.append(f"expected command '{exp_cmd}', got '{actual_cmd}'")
        if exp_args is not None and actual_args != exp_args:
            errors.append(f"expected args {exp_args}, got {actual_args}")

if actual_status != exp_status:
    errors.append(f"expected exit status {exp_status}, got {actual_status}")

if decoy_intact_str != "1":
    errors.append("decoy file integrity check failed: decoy files were altered or expanded")

record = {
    "test_id": test_id,
    "description": desc,
    "mode": mode,
    "alias": alias_name,
    "expected": {
        "command": exp_cmd if exp_cmd != "null" else None,
        "args": exp_args,
        "status": exp_status,
    },
    "actual": {
        "command": actual_cmd if exp_cmd != "null" else None,
        "args": actual_args if exp_cmd != "null" else None,
        "status": actual_status,
        "stderr": actual_stderr,
    },
    "decoy_files_preserved": (decoy_intact_str == "1"),
    "status": "PASS" if not errors else "FAIL",
    "errors": errors,
}

with open(out_json_file, "a", encoding="utf-8") as f:
    f.write(json.dumps(record) + "\n")

if errors:
    print(f"  [FAIL] {test_id}: {desc}")
    for err in errors:
        print(f"         {err}")
    sys.exit(1)
else:
    print(f"  [PASS] {test_id}: {desc}")
    sys.exit(0)
EOF
chmod +x "$test_dir/assert_quoting.py"

local raw_record_file="${RECORD_JSON:-$test_dir/raw_records.jsonl}"
local failed_count=0
local total_count=0

run_quoting_test() {
  local test_id="$1"
  local desc="$2"
  local mode="$3"
  local alias_name="$4"
  local exp_status="$5"
  local exp_cmd="$6"
  local exp_args_json="$7"
  local actual_status="$8"
  local call_log="$9"
  local err_log="${10}"
  local decoy_ok="${11}"

  total_count=$((total_count + 1))

  "$host_python" "$test_dir/assert_quoting.py" \
    "$test_id" "$desc" "$mode" "$alias_name" "$exp_status" \
    "$exp_cmd" "$exp_args_json" "$actual_status" \
    "$call_log" "$err_log" "$decoy_ok" "$raw_record_file"

  if [[ $? -ne 0 ]]; then
    failed_count=$((failed_count + 1))
  fi
}

print -- "--- Running Python Plugin Quoting and Wildcard Tests ---"

# -------------------------------------------------------------
# Case 1: pyfind with additional spaced arguments and wildcards
# -------------------------------------------------------------
test_case_1() {
  local sandbox="$test_dir/case1"
  mkdir -p "$sandbox/test dir with spaces"
  touch "$sandbox/match_decoy.py"
  touch "$sandbox/unrelated_data.txt"

  local call_log="$test_dir/logs/call_1.log"
  local err_log="$test_dir/logs/err_1.log"
  local actual_status=0
  local decoy_ok=0

  (
    cd "$sandbox" || exit 1
    export PATH="$bin_dir:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"

    local before_decoy=$(ls -1)

    source "$plugin_file"
    export STUB_CALL_LOG="$call_log"

    eval 'pyfind -path "*/test dir with spaces/*"' 2>"$err_log"
    local rc=$?

    local after_decoy=$(ls -1)
    [[ "$before_decoy" == "$after_decoy" ]] && decoy_ok=1

    echo "$rc $decoy_ok" > "$test_dir/logs/flags_1"
  )
  read actual_status decoy_ok < "$test_dir/logs/flags_1"

  run_quoting_test \
    "pyfind_spaces_and_wildcard" \
    "pyfind preserves wildcard pattern and spaced path argument intact" \
    "alias_exec" "pyfind" 0 "find" \
    '[".", "-name", "*.py", "-path", "*/test dir with spaces/*"]' \
    "$actual_status" "$call_log" "$err_log" "$decoy_ok"
}
test_case_1

# -------------------------------------------------------------
# Case 2: pygrep with search pattern containing spaces & wildcards
# -------------------------------------------------------------
test_case_2() {
  local sandbox="$test_dir/case2"
  mkdir -p "$sandbox/my code folder"
  echo "target content" > "$sandbox/test_class_match.py"
  echo "unrelated data" > "$sandbox/unrelated.dat"

  local call_log="$test_dir/logs/call_2.log"
  local err_log="$test_dir/logs/err_2.log"
  local actual_status=0
  local decoy_ok=0

  (
    cd "$sandbox" || exit 1
    export PATH="$bin_dir:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"

    local before_files=$(ls -1)

    source "$plugin_file"
    export STUB_CALL_LOG="$call_log"

    eval 'pygrep "class *Controller" "my code folder"' 2>"$err_log"
    local rc=$?

    local after_files=$(ls -1)
    [[ "$before_files" == "$after_files" ]] && decoy_ok=1

    echo "$rc $decoy_ok" > "$test_dir/logs/flags_2"
  )
  read actual_status decoy_ok < "$test_dir/logs/flags_2"

  run_quoting_test \
    "pygrep_pattern_spaces_and_wildcard" \
    "pygrep preserves quoted search pattern with wildcard and spaced path" \
    "alias_exec" "pygrep" 0 "grep" \
    '["-nr", "--include=*.py", "class *Controller", "my code folder"]' \
    "$actual_status" "$call_log" "$err_log" "$decoy_ok"
}
test_case_2

# -------------------------------------------------------------
# Case 3: pyserver with directory containing spaces and port
# -------------------------------------------------------------
test_case_3() {
  local sandbox="$test_dir/case3"
  mkdir -p "$sandbox/public html"
  echo "site index" > "$sandbox/public html/index.html"
  echo "decoy data" > "$sandbox/decoy.txt"

  local call_log="$test_dir/logs/call_3.log"
  local err_log="$test_dir/logs/err_3.log"
  local actual_status=0
  local decoy_ok=0

  (
    cd "$sandbox" || exit 1
    export PATH="$bin_dir:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"

    local before_files=$(ls -1)

    source "$plugin_file"
    export STUB_CALL_LOG="$call_log"

    eval 'pyserver --directory "public html" 8080' 2>"$err_log"
    local rc=$?

    local after_files=$(ls -1)
    [[ "$before_files" == "$after_files" ]] && decoy_ok=1

    echo "$rc $decoy_ok" > "$test_dir/logs/flags_3"
  )
  read actual_status decoy_ok < "$test_dir/logs/flags_3"

  run_quoting_test \
    "pyserver_directory_spaces" \
    "pyserver forwards directory option with spaces and port argument intact" \
    "alias_exec" "pyserver" 0 "python3" \
    '["-m", "http.server", "--directory", "public html", "8080"]' \
    "$actual_status" "$call_log" "$err_log" "$decoy_ok"
}
test_case_3

# -------------------------------------------------------------
# Case 4: pyclean with multiple directories containing spaces
# -------------------------------------------------------------
test_case_4() {
  local sandbox="$test_dir/case4"
  mkdir -p "$sandbox/app folder one" "$sandbox/app folder two"
  echo "decoy archive" > "$sandbox/decoy_archive.zip"

  local call_log="$test_dir/logs/call_4.log"
  local err_log="$test_dir/logs/err_4.log"
  local actual_status=0
  local decoy_ok=0

  (
    cd "$sandbox" || exit 1
    export PATH="$bin_dir:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"

    local before_decoy=$(cat "$sandbox/decoy_archive.zip")

    source "$plugin_file"
    export STUB_CALL_LOG="$call_log"

    eval 'pyclean "app folder one" "app folder two"' 2>"$err_log"
    local rc=$?

    local after_decoy=$(cat "$sandbox/decoy_archive.zip")
    [[ "$before_decoy" == "$after_decoy" ]] && decoy_ok=1

    echo "$rc $decoy_ok" > "$test_dir/logs/flags_4"
  )
  read actual_status decoy_ok < "$test_dir/logs/flags_4"

  run_quoting_test \
    "pyclean_directories_with_spaces" \
    "pyclean passes spaced directory paths as distinct arguments to find" \
    "function_exec" "pyclean" 0 "find" \
    '["app folder one", "app folder two", "-depth", "-type", "d", "-name", ".pytest_cache", "-exec", "rm", "-r", "{}", "+"]' \
    "$actual_status" "$call_log" "$err_log" "$decoy_ok"
}
test_case_4

# -------------------------------------------------------------
# Case 5: Documented failure / edge state with invalid flag
# -------------------------------------------------------------
test_case_5() {
  local sandbox="$test_dir/case5"
  mkdir -p "$sandbox"
  touch "$sandbox/safe_decoy.txt"

  local call_log="$test_dir/logs/call_5.log"
  local err_log="$test_dir/logs/err_5.log"
  local actual_status=0
  local decoy_ok=0

  (
    cd "$sandbox" || exit 1
    export PATH="$bin_dir:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"

    local before_files=$(ls -1)

    source "$plugin_file"
    export STUB_CALL_LOG="$call_log"

    eval 'pygrep --invalid-flag "pattern"' 2>"$err_log"
    local rc=$?

    local after_files=$(ls -1)
    [[ "$before_files" == "$after_files" ]] && decoy_ok=1

    echo "$rc $decoy_ok" > "$test_dir/logs/flags_5"
  )
  read actual_status decoy_ok < "$test_dir/logs/flags_5"

  run_quoting_test \
    "pygrep_invalid_flag_failure" \
    "pygrep propagates failure exit code 2 on invalid option without affecting files" \
    "failure_edge" "pygrep" 2 "grep" \
    '["-nr", "--include=*.py", "--invalid-flag", "pattern"]' \
    "$actual_status" "$call_log" "$err_log" "$decoy_ok"
}
test_case_5

# -------------------------------------------------------------
# Case 6: pyfind from within a directory containing spaces
# -------------------------------------------------------------
test_case_6() {
  local sandbox="$test_dir/case6/project directory with spaces"
  mkdir -p "$sandbox"
  touch "$sandbox/app_script.py"
  touch "$sandbox/decoy.txt"

  local call_log="$test_dir/logs/call_6.log"
  local err_log="$test_dir/logs/err_6.log"
  local actual_status=0
  local decoy_ok=0

  (
    cd "$sandbox" || exit 1
    export PATH="$bin_dir:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"

    local before_files=$(ls -1)

    source "$plugin_file"
    export STUB_CALL_LOG="$call_log"

    eval 'pyfind' 2>"$err_log"
    local rc=$?

    local after_files=$(ls -1)
    [[ "$before_files" == "$after_files" ]] && decoy_ok=1

    echo "$rc $decoy_ok" > "$test_dir/logs/flags_6"
  )
  read actual_status decoy_ok < "$test_dir/logs/flags_6"

  run_quoting_test \
    "pyfind_in_spaced_directory" \
    "pyfind executes from within a spaced directory path preserving dot context" \
    "alias_exec" "pyfind" 0 "find" \
    '[".", "-name", "*.py"]' \
    "$actual_status" "$call_log" "$err_log" "$decoy_ok"
}
test_case_6

print -- "---------------------------------------------------"
print -- "Test Suite Finished: $((total_count - failed_count))/$total_count passed ($failed_count failed)"

if [[ $failed_count -ne 0 ]]; then
  exit 1
fi
exit 0
