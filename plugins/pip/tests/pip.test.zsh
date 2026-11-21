#!/usr/bin/env zsh

emulate -LR zsh

# Ensure aliases are parsed and expanded for testing
setopt aliases

# Resolve repository and plugin paths
local plugin_file="${0:A:h:h}/pip.plugin.zsh"
if [[ ! -f "$plugin_file" ]]; then
  print -u2 -r -- "FAIL: Cannot find pip.plugin.zsh at $plugin_file"
  exit 1
fi

local test_dir=$(mktemp -d) || exit 1
trap 'command rm -rf -- "$test_dir"' EXIT INT TERM

# Ensure isolation: point ZDOTDIR and HOME to temp directory
export ZDOTDIR="$test_dir/zdotdir"
export HOME="$test_dir/home"
mkdir -p "$ZDOTDIR" "$HOME"
export ZSH="${ZSH:-${0:A:h:h:h:h}}"

# Ensure host Python is accessible
local host_tools="$test_dir/host_tools"
mkdir -p "$host_tools"
local host_python="${PYTHON_BIN:-${commands[python3]:-$(command -v python3 2>/dev/null)}}"
if [[ -n "$host_python" && -x "$host_python" ]]; then
  ln -sf "$host_python" "$host_tools/python3"
  ln -sf "$host_python" "$host_tools/python"
fi

# Create isolated bin directories for pip mode and pip3-only mode
local bin_pip="$test_dir/bin_pip"
local bin_pip3_only="$test_dir/bin_pip3_only"
mkdir -p "$bin_pip" "$bin_pip3_only"

# Create mock stub executable
cat << 'EOF' > "$test_dir/mock_stub"
#!/usr/bin/env python3
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

# Check argument contract constraints
if len(args) == 0:
    sys.exit(0)

subcmd = args[0]
sub_args = args[1:]

if subcmd == "install":
    reqs = [a for a in sub_args if not a.startswith("-")]
    flags = [a for a in sub_args if a.startswith("-")]
    # Mutually exclusive options check
    if ("--user" in flags and "--prefix" in flags) or ("--user" in flags and "--target" in flags):
        sys.stderr.write("ERROR: Can not combine '--user' and '--prefix' as they imply different installation locations\n")
        sys.exit(1)
    # Check if any requirement was provided (package or -r file)
    has_req = bool(reqs) or ("-r" in sub_args or "--requirement" in sub_args)
    if not has_req:
        sys.stderr.write("ERROR: You must give at least one requirement to install (see \"pip help install\")\n")
        sys.exit(1)

elif subcmd == "uninstall":
    reqs = [a for a in sub_args if not a.startswith("-")]
    if "--no-cache-dir" in sub_args:
        sys.stderr.write("ERROR: no such option: --no-cache-dir\n")
        sys.exit(2)
    has_req = bool(reqs) or ("-r" in sub_args or "--requirement" in sub_args)
    if not has_req:
        sys.stderr.write("ERROR: You must give at least one requirement to uninstall (see \"pip help uninstall\")\n")
        sys.exit(1)

sys.exit(0)
EOF
chmod +x "$test_dir/mock_stub"

# Set up bin_pip: has both pip and pip3 stubs
ln -s "$test_dir/mock_stub" "$bin_pip/pip"
ln -s "$test_dir/mock_stub" "$bin_pip/pip3"

# Set up bin_pip3_only: has only pip3 stub (pip is absent)
ln -s "$test_dir/mock_stub" "$bin_pip3_only/pip3"

# Assertion helper
cat << 'EOF' > "$test_dir/assert_test.py"
#!/usr/bin/env python3
import sys, json, os

(
    _, call_log, err_log, test_id, desc, mode, alias_name,
    exp_cmd, exp_status_str, exp_args_json, in_args_json,
    out_json_file
) = sys.argv[:12]

errors = []
exp_status = int(exp_status_str)
exp_args = json.loads(exp_args_json)
in_args = json.loads(in_args_json)

actual_cmd = ""
actual_args = []
actual_stderr = ""

if os.path.exists(call_log):
    with open(call_log, "r", encoding="utf-8") as f:
        data = json.load(f)
        actual_cmd = data.get("command", "")
        actual_args = data.get("args", [])
else:
    errors.append("call log not generated: command was not invoked")

if os.path.exists(err_log):
    with open(err_log, "r", encoding="utf-8") as f:
        actual_stderr = f.read()

actual_status_str = os.environ.get("ACTUAL_STATUS", "-1")
try:
    actual_status = int(actual_status_str)
except ValueError:
    actual_status = -1

if actual_cmd != exp_cmd:
    errors.append(f"expected command '{exp_cmd}', got '{actual_cmd}'")

if actual_args != exp_args:
    errors.append(f"expected args {exp_args}, got {actual_args}")

if actual_status != exp_status:
    errors.append(f"expected exit status {exp_status}, got {actual_status}")

record = {
    "test_id": test_id,
    "description": desc,
    "mode": mode,
    "alias": alias_name,
    "inputs": {"args": in_args},
    "expected": {
        "command": exp_cmd,
        "args": exp_args,
        "status": exp_status,
    },
    "actual": {
        "command": actual_cmd,
        "args": actual_args,
        "status": actual_status,
        "stderr": actual_stderr,
    },
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
chmod +x "$test_dir/assert_test.py"

local raw_record_file="${RECORD_JSON:-$test_dir/raw_records.jsonl}"
local failed_count=0
local total_count=0

run_fixture_test() {
  local test_id="$1"
  local desc="$2"
  local mode="$3"
  local alias_name="$4"
  local exp_cmd="$5"
  local exp_status="$6"
  local exp_args_json="$7"
  local in_args_json="$8"
  local test_cmd_str="$9"

  total_count=$((total_count + 1))
  local call_log="$test_dir/call_${total_count}.json"
  local err_log="$test_dir/err_${total_count}.log"
  rm -f "$call_log" "$err_log"

  local bin_path
  if [[ "$mode" == "pip_mode" ]]; then
    bin_path="$bin_pip:$host_tools:/bin:/usr/bin"
  else
    bin_path="$bin_pip3_only:$host_tools:/bin:/usr/bin"
  fi

  local status_file="$test_dir/status_${total_count}"
  (
    export PATH="$bin_path"
    export STUB_CALL_LOG="$call_log"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"

    # Stub compdef if not provided by environment
    compdef() { : }

    # Enable aliases, reset and load plugin
    setopt aliases
    unalias -m '*' 2>/dev/null
    source "$plugin_file"

    eval "$test_cmd_str" 2>"$err_log"
    echo "$?" > "$status_file"
  )

  local actual_status
  if [[ -f "$status_file" ]]; then
    actual_status=$(cat "$status_file")
  else
    actual_status=-1
  fi

  ACTUAL_STATUS="$actual_status" "$host_python" "$test_dir/assert_test.py" \
    "$call_log" "$err_log" "$test_id" "$desc" "$mode" "$alias_name" \
    "$exp_cmd" "$exp_status" "$exp_args_json" "$in_args_json" \
    "$raw_record_file"

  if [[ $? -ne 0 ]]; then
    failed_count=$((failed_count + 1))
  fi
}

print -- "--- Running Pip Plugin Argument Contract Tests ---"

# -------------------------------------------------------------
# 1. pipi (pip install) tests
# -------------------------------------------------------------
run_fixture_test \
  "pipi_min_args" \
  "pipi with minimum accepted arguments (single package)" \
  "pip_mode" "pipi" "pip" 0 \
  '["install", "requests"]' '["requests"]' \
  'pipi requests'

run_fixture_test \
  "pipi_optional_flag" \
  "pipi with optional flag --no-deps" \
  "pip_mode" "pipi" "pip" 0 \
  '["install", "requests", "--no-deps"]' '["requests", "--no-deps"]' \
  'pipi requests --no-deps'

run_fixture_test \
  "pipi_quoted_and_spaces" \
  "pipi preserves spaces and quotes in arguments" \
  "pip_mode" "pipi" "pip" 0 \
  '["install", "requests >= 2.28.0", "--target", "/path with spaces"]' \
  '["requests >= 2.28.0", "--target", "/path with spaces"]' \
  'pipi "requests >= 2.28.0" --target "/path with spaces"'

run_fixture_test \
  "pipi_noglob_brackets" \
  "pipi with bracket extra syntax preserves noglob literal argument" \
  "pip_mode" "pipi" "pip" 0 \
  '["install", "requests[security]"]' '["requests[security]"]' \
  'pipi requests[security]'

run_fixture_test \
  "pipi_invalid_combination_user_prefix" \
  "pipi rejects documented mutually exclusive combination (--user and --prefix)" \
  "pip_mode" "pipi" "pip" 1 \
  '["install", "--user", "--prefix", "/opt/custom", "requests"]' \
  '["--user", "--prefix", "/opt/custom", "requests"]' \
  'pipi --user --prefix /opt/custom requests'

run_fixture_test \
  "pipi_bare_invocation_failure" \
  "pipi bare invocation without requirements triggers documented failure" \
  "pip_mode" "pipi" "pip" 1 \
  '["install"]' '[]' \
  'pipi'

# -------------------------------------------------------------
# 2. pipu (pip install --upgrade) tests
# -------------------------------------------------------------
run_fixture_test \
  "pipu_min_args" \
  "pipu with minimum accepted arguments (single package)" \
  "pip_mode" "pipu" "pip" 0 \
  '["install", "--upgrade", "requests"]' '["requests"]' \
  'pipu requests'

run_fixture_test \
  "pipu_optional_flag" \
  "pipu with optional flag --no-deps" \
  "pip_mode" "pipu" "pip" 0 \
  '["install", "--upgrade", "requests", "--no-deps"]' '["requests", "--no-deps"]' \
  'pipu requests --no-deps'

run_fixture_test \
  "pipu_quoted_and_spaces" \
  "pipu preserves version specifier spaces and option arguments" \
  "pip_mode" "pipu" "pip" 0 \
  '["install", "--upgrade", "requests >= 2.28.0"]' '["requests >= 2.28.0"]' \
  'pipu "requests >= 2.28.0"'

run_fixture_test \
  "pipu_invalid_combination_user_prefix" \
  "pipu rejects documented mutually exclusive combination (--user and --prefix)" \
  "pip_mode" "pipu" "pip" 1 \
  '["install", "--upgrade", "--user", "--prefix", "/opt/custom", "requests"]' \
  '["--user", "--prefix", "/opt/custom", "requests"]' \
  'pipu --user --prefix /opt/custom requests'

run_fixture_test \
  "pipu_bare_invocation_failure" \
  "pipu bare invocation without requirements triggers documented failure" \
  "pip_mode" "pipu" "pip" 1 \
  '["install", "--upgrade"]' '[]' \
  'pipu'

# -------------------------------------------------------------
# 3. pipun (pip uninstall) tests
# -------------------------------------------------------------
run_fixture_test \
  "pipun_min_args" \
  "pipun with minimum accepted arguments (single package)" \
  "pip_mode" "pipun" "pip" 0 \
  '["uninstall", "requests"]' '["requests"]' \
  'pipun requests'

run_fixture_test \
  "pipun_optional_flag_yes" \
  "pipun with optional confirmation flag -y" \
  "pip_mode" "pipun" "pip" 0 \
  '["uninstall", "-y", "requests"]' '["-y", "requests"]' \
  'pipun -y requests'

run_fixture_test \
  "pipun_quoted_spaces" \
  "pipun preserves quoted package name with spaces" \
  "pip_mode" "pipun" "pip" 0 \
  '["uninstall", "custom package name"]' '["custom package name"]' \
  'pipun "custom package name"'

run_fixture_test \
  "pipun_invalid_option" \
  "pipun rejects documented invalid option --no-cache-dir" \
  "pip_mode" "pipun" "pip" 2 \
  '["uninstall", "--no-cache-dir", "requests"]' '["--no-cache-dir", "requests"]' \
  'pipun --no-cache-dir requests'

run_fixture_test \
  "pipun_bare_invocation_failure" \
  "pipun bare invocation without requirements triggers documented failure" \
  "pip_mode" "pipun" "pip" 1 \
  '["uninstall"]' '[]' \
  'pipun'

# -------------------------------------------------------------
# 4. pip3 fallback environment tests (when pip binary is missing)
# -------------------------------------------------------------
run_fixture_test \
  "pip3_fallback_pipi" \
  "pipi invokes pip3 when pip binary is missing from PATH" \
  "pip3_only_mode" "pipi" "pip3" 0 \
  '["install", "requests"]' '["requests"]' \
  'pipi requests'

run_fixture_test \
  "pip3_fallback_pipu" \
  "pipu invokes pip3 when pip binary is missing from PATH" \
  "pip3_only_mode" "pipu" "pip3" 0 \
  '["install", "--upgrade", "requests"]' '["requests"]' \
  'pipu requests'

run_fixture_test \
  "pip3_fallback_pipun" \
  "pipun invokes pip3 when pip binary is missing from PATH" \
  "pip3_only_mode" "pipun" "pip3" 0 \
  '["uninstall", "requests"]' '["requests"]' \
  'pipun requests'

# -------------------------------------------------------------
# 5. Exit status propagation check
# -------------------------------------------------------------
run_fixture_custom_status() {
  local test_id="exit_status_propagation"
  local desc="pipi propagates arbitrary non-zero exit status (code 42)"
  total_count=$((total_count + 1))
  local call_log="$test_dir/call_${total_count}.json"
  local err_log="$test_dir/err_${total_count}.log"
  local status_file="$test_dir/status_${total_count}"

  (
    export PATH="$bin_pip:$host_tools:/bin:/usr/bin"
    export STUB_CALL_LOG="$call_log"
    export STUB_EXIT_STATUS="42"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"

    compdef() { : }
    setopt aliases
    unalias -m '*' 2>/dev/null
    source "$plugin_file"

    eval 'pipi requests' 2>"$err_log"
    echo "$?" > "$status_file"
  )

  local actual_status=$(cat "$status_file")
  ACTUAL_STATUS="$actual_status" "$host_python" "$test_dir/assert_test.py" \
    "$call_log" "$err_log" "$test_id" "$desc" "pip_mode" "pipi" \
    "pip" "42" '["install", "requests"]' '["requests"]' \
    "$raw_record_file"

  if [[ $? -ne 0 ]]; then
    failed_count=$((failed_count + 1))
  fi
}
run_fixture_custom_status

print -- "---------------------------------------------------"
print -- "Test Suite Finished: $((total_count - failed_count))/$total_count passed ($failed_count failed)"

if [[ $failed_count -ne 0 ]]; then
  exit 1
fi
exit 0
