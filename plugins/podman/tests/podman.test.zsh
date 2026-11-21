#!/usr/bin/env zsh

emulate -LR zsh
setopt aliases

# Resolve plugin path
local plugin_file="${0:A:h:h}/podman.plugin.zsh"
if [[ ! -f "$plugin_file" ]]; then
  print -u2 -r -- "FAIL: Cannot find podman.plugin.zsh at $plugin_file"
  exit 1
fi

local test_dir=$(mktemp -d) || exit 1
trap 'command rm -rf -- "$test_dir"' EXIT INT TERM

# Ensure isolation
export ZDOTDIR="$test_dir/zdotdir"
export HOME="$test_dir/home"
export ZSH_CACHE_DIR="$test_dir/cache"
export ZSH="${ZSH:-${0:A:h:h:h:h}}"
mkdir -p "$ZDOTDIR" "$HOME" "$ZSH_CACHE_DIR/completions"

# Host Python
local host_tools="$test_dir/host_tools"
mkdir -p "$host_tools"
local host_python="${PYTHON_BIN:-${commands[python3]:-$(command -v python3 2>/dev/null)}}"
if [[ -n "$host_python" && -x "$host_python" ]]; then
  ln -sf "$host_python" "$host_tools/python3"
  ln -sf "$host_python" "$host_tools/python"
fi

# Isolated bin directories
local bin_podman="$test_dir/bin_podman"
local bin_empty="$test_dir/bin_empty"
mkdir -p "$bin_podman" "$bin_empty"

# Mock stub executable for podman
cat << 'EOF' > "$test_dir/mock_podman"
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

# Handle subcommands
if len(args) == 0:
    sys.exit(0)

if args[0] == "completion":
    sys.stdout.write("#compdef podman\n_podman() { }\n")
    sys.exit(0)

if args[0] == "build":
    # Minimum arguments: needs a context path
    flags = [a for a in args[1:] if a.startswith("-")]
    targets = [a for a in args[1:] if not a.startswith("-") and not (flags and a in ["Dockerfile", "Containerfile"])]
    if not targets:
        sys.stderr.write("Error: \"podman build\" requires at least 1 argument\n")
        sys.exit(125)
    sys.exit(0)

if args[0] == "container":
    if len(args) < 2:
        sys.exit(0)
    sub = args[1]
    sub_args = args[2:]
    if sub == "inspect":
        containers = [a for a in sub_args if not a.startswith("-") and not (len(sub_args) > 1 and sub_args[sub_args.index(a)-1] == "--format")]
        if not containers:
            sys.stderr.write("Error: \"podman container inspect\" requires at least 1 argument\n")
            sys.exit(125)
        sys.exit(0)
    elif sub == "ls":
        sys.exit(0)

sys.exit(0)
EOF
chmod +x "$test_dir/mock_podman"
ln -s "$test_dir/mock_podman" "$bin_podman/podman"

# Test assertion evaluator
cat << 'EOF' > "$test_dir/assert_state.py"
#!/usr/bin/env python3
import sys, json, os

(
    _, test_id, desc, mode, alias_name, exp_status_str,
    exp_cmd, exp_args_json, actual_status_str,
    call_log_path, err_log_path, intended_ok_str, intended_detail,
    unrelated_ok_str, unrelated_detail, out_json_file
) = sys.argv[:16]

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

intended_satisfied = (intended_ok_str == "1")
if not intended_satisfied:
    errors.append(f"intended state change failed: {intended_detail}")

unrelated_satisfied = (unrelated_ok_str == "1")
if not unrelated_satisfied:
    errors.append(f"unrelated state check failed: {unrelated_detail}")

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
    "state_transitions": {
        "intended_change": {
            "satisfied": intended_satisfied,
            "detail": intended_detail,
        },
        "unrelated_state": {
            "satisfied": unrelated_satisfied,
            "detail": unrelated_detail,
        },
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
chmod +x "$test_dir/assert_state.py"

local raw_record_file="${RECORD_JSON:-$test_dir/raw_records.jsonl}"
local failed_count=0
local total_count=0

run_state_test() {
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
  local intended_ok="${11}"
  local intended_detail="${12}"
  local unrelated_ok="${13}"
  local unrelated_detail="${14}"

  total_count=$((total_count + 1))

  "$host_python" "$test_dir/assert_state.py" \
    "$test_id" "$desc" "$mode" "$alias_name" "$exp_status" \
    "$exp_cmd" "$exp_args_json" "$actual_status" \
    "$call_log" "$err_log" "$intended_ok" "$intended_detail" \
    "$unrelated_ok" "$unrelated_detail" "$raw_record_file"

  if [[ $? -ne 0 ]]; then
    failed_count=$((failed_count + 1))
  fi
}

print -- "--- Running Podman Plugin State Transition Tests ---"

# -------------------------------------------------------------
# Case 1: Shell Definitions Transition (Plugin Load with Podman)
# -------------------------------------------------------------
test_case_1() {
  local sandbox="$test_dir/case1"
  mkdir -p "$sandbox"
  local err_log="$sandbox/err.log"
  local call_log="$sandbox/call.log"

  local actual_status=0
  local intended_ok=0
  local unrelated_ok=0

  (
    export PATH="$bin_podman:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export ZSH_CACHE_DIR="$sandbox/cache"
    mkdir -p "$ZSH_CACHE_DIR/completions"

    alias unrelated_decoy_alias='echo untouched'
    local UNRELATED_ENV_VAR="preserved_value_42"

    local before_pbl_set=0
    local before_pcin_set=0
    local before_pcls_set=0
    local before_unrelated_set=0

    (( $+aliases[pbl] )) && before_pbl_set=1
    (( $+aliases[pcin] )) && before_pcin_set=1
    (( $+aliases[pcls] )) && before_pcls_set=1
    [[ "${aliases[unrelated_decoy_alias]}" == "echo untouched" ]] && before_unrelated_set=1

    source "$plugin_file" 2>"$err_log"

    local after_pbl_set=0
    local after_pcin_set=0
    local after_pcls_set=0
    local after_unrelated_set=0

    [[ "${aliases[pbl]}" == "podman build" ]] && after_pbl_set=1
    [[ "${aliases[pcin]}" == "podman container inspect" ]] && after_pcin_set=1
    [[ "${aliases[pcls]}" == "podman container ls" ]] && after_pcls_set=1
    [[ "${aliases[unrelated_decoy_alias]}" == "echo untouched" ]] && after_unrelated_set=1

    if (( before_pbl_set == 0 && before_pcin_set == 0 && before_pcls_set == 0 && \
          after_pbl_set == 1 && after_pcin_set == 1 && after_pcls_set == 1 )); then
      intended_ok=1
    fi

    if (( before_unrelated_set == 1 && after_unrelated_set == 1 && \
          UNRELATED_ENV_VAR == "preserved_value_42" )); then
      unrelated_ok=1
    fi

    echo "$intended_ok $unrelated_ok" > "$sandbox/flags"
  )
  read intended_ok unrelated_ok < "$sandbox/flags"

  run_state_test \
    "podman_load_shell_transition" \
    "plugin load transitions pbl, pcin, pcls aliases while preserving unrelated shell state" \
    "plugin_load" "source" 0 "null" "null" "$actual_status" \
    "$call_log" "$err_log" "$intended_ok" \
    "aliases pbl, pcin, pcls transitioned from unset to defined" \
    "$unrelated_ok" \
    "unrelated_decoy_alias and UNRELATED_ENV_VAR remained unchanged"
}
test_case_1

# -------------------------------------------------------------
# Case 2: Filesystem & Completion State Transition
# -------------------------------------------------------------
test_case_2() {
  local sandbox="$test_dir/case2"
  mkdir -p "$sandbox/cache/completions"
  local err_log="$sandbox/err.log"
  local call_log="$sandbox/call.log"

  local actual_status=0
  local intended_ok=0
  local unrelated_ok=0

  (
    export PATH="$bin_podman:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export ZSH_CACHE_DIR="$sandbox/cache"

    echo "decoy_content_untouched" > "$ZSH_CACHE_DIR/completions/decoy.txt"

    local before_comps_val="${_comps[podman]:-unset}"
    local before_decoy_content=$(cat "$ZSH_CACHE_DIR/completions/decoy.txt")

    source "$plugin_file" 2>"$err_log"
    wait 2>/dev/null

    local after_comps_val="${_comps[podman]:-unset}"
    local after_decoy_content=$(cat "$ZSH_CACHE_DIR/completions/decoy.txt")

    [[ "$before_comps_val" == "unset" && "$after_comps_val" == "_podman" ]] && intended_ok=1
    [[ "$before_decoy_content" == "decoy_content_untouched" && "$after_decoy_content" == "decoy_content_untouched" ]] && unrelated_ok=1

    echo "$intended_ok $unrelated_ok" > "$sandbox/flags"
  )
  read intended_ok unrelated_ok < "$sandbox/flags"

  run_state_test \
    "podman_completion_state_transition" \
    "plugin sets _comps[podman]=_podman while preserving unrelated completion decoy files" \
    "completion_setup" "autoload" 0 "null" "null" "$actual_status" \
    "$call_log" "$err_log" "$intended_ok" \
    "_comps[podman] transitioned from unset to _podman" \
    "$unrelated_ok" \
    "decoy.txt content remained unchanged"
}
test_case_2

# -------------------------------------------------------------
# Case 3: pbl (podman build) State Transition and Argument Vector
# -------------------------------------------------------------
test_case_3() {
  local sandbox="$test_dir/case3"
  mkdir -p "$sandbox/project"
  touch "$sandbox/project/Dockerfile"
  echo '{"unrelated": true}' > "$sandbox/project/unrelated_decoy.json"

  local call_log="$sandbox/call_pbl.json"
  local err_log="$sandbox/err_pbl.log"
  local actual_status=0
  local intended_ok=0
  local unrelated_ok=0

  (
    cd "$sandbox/project" || exit 1
    export PATH="$bin_podman:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export ZSH_CACHE_DIR="$sandbox/cache"
    mkdir -p "$ZSH_CACHE_DIR/completions"

    local before_pwd="$PWD"
    local before_decoy=$(cat "$sandbox/project/unrelated_decoy.json")

    source "$plugin_file"
    wait 2>/dev/null

    export STUB_CALL_LOG="$call_log"

    eval 'pbl -t "custom-app:v1.0" -f Dockerfile .' 2>"$err_log"
    local rc=$?

    local after_pwd="$PWD"
    local after_decoy=$(cat "$sandbox/project/unrelated_decoy.json")

    [[ $rc -eq 0 && -f "$call_log" ]] && intended_ok=1
    [[ "$before_pwd" == "$after_pwd" && "$before_decoy" == "$after_decoy" ]] && unrelated_ok=1

    echo "$rc $intended_ok $unrelated_ok" > "$sandbox/flags"
  )
  read actual_status intended_ok unrelated_ok < "$sandbox/flags"

  run_state_test \
    "pbl_build_state_transition" \
    "pbl forwards tag/file args to podman build while preserving working directory and decoy files" \
    "alias_exec" "pbl" 0 "podman" \
    '["build", "-t", "custom-app:v1.0", "-f", "Dockerfile", "."]' \
    "$actual_status" "$call_log" "$err_log" "$intended_ok" \
    "pbl executed podman build with forwarded arguments" \
    "$unrelated_ok" \
    "working directory and unrelated_decoy.json remained identical"
}
test_case_3

# -------------------------------------------------------------
# Case 4: pcin (podman container inspect) State Transition
# -------------------------------------------------------------
test_case_4() {
  local sandbox="$test_dir/case4"
  mkdir -p "$sandbox"
  echo "safe_unrelated_marker" > "$sandbox/unrelated.txt"

  local call_log="$sandbox/call_pcin.json"
  local err_log="$sandbox/err_pcin.log"
  local actual_status=0
  local intended_ok=0
  local unrelated_ok=0

  (
    export PATH="$bin_podman:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export ZSH_CACHE_DIR="$sandbox/cache"
    mkdir -p "$ZSH_CACHE_DIR/completions"

    local before_content=$(cat "$sandbox/unrelated.txt")

    source "$plugin_file"
    wait 2>/dev/null

    export STUB_CALL_LOG="$call_log"

    eval 'pcin --format "{{.State.Status}}" "my-redis-container"' 2>"$err_log"
    local rc=$?

    local after_content=$(cat "$sandbox/unrelated.txt")

    [[ $rc -eq 0 && -f "$call_log" ]] && intended_ok=1
    [[ "$before_content" == "$after_content" ]] && unrelated_ok=1

    echo "$rc $intended_ok $unrelated_ok" > "$sandbox/flags"
  )
  read actual_status intended_ok unrelated_ok < "$sandbox/flags"

  run_state_test \
    "pcin_inspect_state_transition" \
    "pcin executes container inspect preserving format quotes and leaving files intact" \
    "alias_exec" "pcin" 0 "podman" \
    '["container", "inspect", "--format", "{{.State.Status}}", "my-redis-container"]' \
    "$actual_status" "$call_log" "$err_log" "$intended_ok" \
    "pcin invoked podman container inspect with format string and container name" \
    "$unrelated_ok" \
    "unrelated.txt remained unchanged"
}
test_case_4

# -------------------------------------------------------------
# Case 5: pcls (podman container ls) State Transition
# -------------------------------------------------------------
test_case_5() {
  local sandbox="$test_dir/case5"
  mkdir -p "$sandbox"

  local call_log="$sandbox/call_pcls.json"
  local err_log="$sandbox/err_pcls.log"
  local actual_status=0
  local intended_ok=0
  local unrelated_ok=0

  (
    export PATH="$bin_podman:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export ZSH_CACHE_DIR="$sandbox/cache"
    mkdir -p "$ZSH_CACHE_DIR/completions"

    alias unrelated_ls_alias='ls -la'
    local before_alias="${aliases[unrelated_ls_alias]}"

    source "$plugin_file"
    wait 2>/dev/null

    export STUB_CALL_LOG="$call_log"

    eval 'pcls -a --format "{{.ID}}"' 2>"$err_log"
    local rc=$?

    local after_alias="${aliases[unrelated_ls_alias]}"

    [[ $rc -eq 0 && -f "$call_log" ]] && intended_ok=1
    [[ "$before_alias" == "$after_alias" ]] && unrelated_ok=1

    echo "$rc $intended_ok $unrelated_ok" > "$sandbox/flags"
  )
  read actual_status intended_ok unrelated_ok < "$sandbox/flags"

  run_state_test \
    "pcls_ls_state_transition" \
    "pcls executes container ls -a and preserves unrelated alias definitions" \
    "alias_exec" "pcls" 0 "podman" \
    '["container", "ls", "-a", "--format", "{{.ID}}"]' \
    "$actual_status" "$call_log" "$err_log" "$intended_ok" \
    "pcls forwarded container ls arguments" \
    "$unrelated_ok" \
    "unrelated_ls_alias remained unchanged"
}
test_case_5

# -------------------------------------------------------------
# Case 6: Edge/Failure State Transition (Bare pcin without container)
# -------------------------------------------------------------
test_case_6() {
  local sandbox="$test_dir/case6"
  mkdir -p "$sandbox"
  echo "precious_data" > "$sandbox/precious.dat"

  local call_log="$sandbox/call_pcin_fail.json"
  local err_log="$sandbox/err_pcin_fail.log"
  local actual_status=0
  local intended_ok=0
  local unrelated_ok=0

  (
    export PATH="$bin_podman:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export ZSH_CACHE_DIR="$sandbox/cache"
    mkdir -p "$ZSH_CACHE_DIR/completions"

    local before_content=$(cat "$sandbox/precious.dat")

    source "$plugin_file"
    wait 2>/dev/null

    export STUB_CALL_LOG="$call_log"

    eval 'pcin' 2>"$err_log"
    local rc=$?

    local after_content=$(cat "$sandbox/precious.dat")

    [[ $rc -eq 125 && -f "$call_log" ]] && intended_ok=1
    [[ "$before_content" == "$after_content" ]] && unrelated_ok=1

    echo "$rc $intended_ok $unrelated_ok" > "$sandbox/flags"
  )
  read actual_status intended_ok unrelated_ok < "$sandbox/flags"

  run_state_test \
    "pcin_bare_failure_transition" \
    "bare pcin propagates failure exit status 125 without mutating unrelated files" \
    "failure_edge" "pcin" 125 "podman" \
    '["container", "inspect"]' \
    "$actual_status" "$call_log" "$err_log" "$intended_ok" \
    "bare pcin returned failure status 125 with diagnostic" \
    "$unrelated_ok" \
    "precious.dat file content remained intact"
}
test_case_6

# -------------------------------------------------------------
# Case 7: Missing Command Guard State Transition
# -------------------------------------------------------------
test_case_7() {
  local sandbox="$test_dir/case7"
  mkdir -p "$sandbox"
  local err_log="$sandbox/err.log"
  local call_log="$sandbox/call.log"

  local actual_status=0
  local intended_ok=0
  local unrelated_ok=0

  (
    export PATH="$bin_empty:$host_tools:/bin:/usr/bin"
    export ZDOTDIR="$test_dir/zdotdir"
    export HOME="$test_dir/home"
    export ZSH_CACHE_DIR="$sandbox/cache"
    mkdir -p "$ZSH_CACHE_DIR/completions"

    alias custom_guard_test='echo active'
    local before_alias="${aliases[custom_guard_test]}"

    source "$plugin_file" 2>"$err_log"

    local after_alias="${aliases[custom_guard_test]}"
    local podman_aliases_count=0
    (( $+aliases[pbl] )) && podman_aliases_count=$((podman_aliases_count + 1))
    (( $+aliases[pcin] )) && podman_aliases_count=$((podman_aliases_count + 1))
    (( $+aliases[pcls] )) && podman_aliases_count=$((podman_aliases_count + 1))

    [[ $podman_aliases_count -eq 0 ]] && intended_ok=1
    [[ "$before_alias" == "$after_alias" ]] && unrelated_ok=1

    echo "$intended_ok $unrelated_ok" > "$sandbox/flags"
  )
  read intended_ok unrelated_ok < "$sandbox/flags"

  run_state_test \
    "podman_missing_guard_transition" \
    "missing podman executable guards shell definitions without affecting existing aliases" \
    "guard_check" "return" 0 "null" "null" "$actual_status" \
    "$call_log" "$err_log" "$intended_ok" \
    "missing podman command caused early return with 0 podman aliases defined" \
    "$unrelated_ok" \
    "custom_guard_test alias remained intact"
}
test_case_7

print -- "---------------------------------------------------"
print -- "Test Suite Finished: $((total_count - failed_count))/$total_count passed ($failed_count failed)"

if [[ $failed_count -ne 0 ]]; then
  exit 1
fi
exit 0
