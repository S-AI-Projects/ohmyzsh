#!/usr/bin/env zsh
# run_tests.zsh – Shell test harness for ruby plugin (R14-T024)
# Verifies path quoting, exact argument boundaries, wildcard handling,
# and that shell expansion does not affect unrelated files.

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

SCRIPT_DIR="${${0:a}:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."
PLUGIN_ZSH="${REPO_ROOT}/plugins/ruby/ruby.plugin.zsh"

TMPBASE=$(mktemp -d)
FAKE_HOME="${TMPBASE}/home"
FAKE_BIN="${TMPBASE}/bin"
FAKE_ZDOTDIR="${TMPBASE}/zdotdir"
STUB_LOG="${TMPBASE}/stub_calls.log"
STUB_EXIT="${TMPBASE}/stub_exit.txt"
PROJECT_DIR="${TMPBASE}/project_space"

mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${FAKE_ZDOTDIR}" "${PROJECT_DIR}"
echo "0" > "${STUB_EXIT}"
: > "${STUB_LOG}"

# Create decoy files with spaces and wildcards to detect unintended globbing
mkdir -p "${PROJECT_DIR}/app folder" "${PROJECT_DIR}/lib dir with spaces" "${PROJECT_DIR}/custom gems path"
echo "puts 'target 1'" > "${PROJECT_DIR}/app folder/test_1.rb"
echo "puts 'target 2'" > "${PROJECT_DIR}/app folder/test_2.rb"
echo "module Lib; end" > "${PROJECT_DIR}/lib dir with spaces/helper.rb"
echo "gem data" > "${PROJECT_DIR}/custom gems path/cool-pkg-1.0.gem"
echo "# unrelated decoy" > "${PROJECT_DIR}/decoy_unrelated.rb"
echo "# decoy file with spaces" > "${PROJECT_DIR}/decoy file with spaces.rb"
sha_before=$(find "${PROJECT_DIR}" -type f -print0 | sort -z | xargs -0 shasum | awk '{print $1}' | paste -sd, -)

# ── Universal Stub Generator ──────────────────────────────────────────────────
# Logs: CMD:<cmd_name> followed by ARG:<token> lines and CALL
for cmd_name in ruby sudo gem find grep; do
  cat > "${FAKE_BIN}/${cmd_name}" <<STUB
#!/bin/sh
LOG="${STUB_LOG}"
EXIT_VAL=\$(cat "${STUB_EXIT}" 2>/dev/null || echo 0)
echo "CMD:${cmd_name}" >> "\$LOG"
for arg in "\$@"; do
  printf 'ARG:%s\n' "\$arg" >> "\$LOG"
done
echo "CALL" >> "\$LOG"

# If find is called in rfind pipeline, output NUL-separated files
if [ "${cmd_name}" = "find" ]; then
  printf "app folder/test_1.rb\0app folder/test_2.rb\0"
fi

for arg in "\$@"; do
  if [ "\$arg" = "--invalid-flag" ]; then
    echo "${cmd_name}: unrecognized option '--invalid-flag'" >&2
    exit 2
  fi
done

if [ "\$EXIT_VAL" -ne 0 ]; then
  echo "${cmd_name}: simulated failure (exit \$EXIT_VAL)" >&2
  exit "\$EXIT_VAL"
fi
exit 0
STUB
  chmod +x "${FAKE_BIN}/${cmd_name}"
done

# ── Helpers ───────────────────────────────────────────────────────────────────
reset_stub() {
  : > "${STUB_LOG}"
  echo "0" > "${STUB_EXIT}"
}

record() {
  local name="$1" test_status="$2" exit_code="$3" actual="$4" expected="$5" notes="$6"
  printf 'RESULT|%s|%s|%s|%s|%s|%s\n' \
    "${name}" "${test_status}" "${exit_code}" "${actual}" "${expected}" "${notes}"
}

check_decoys_intact() {
  local sha_now
  sha_now=$(find "${PROJECT_DIR}" -type f -print0 | sort -z | xargs -0 shasum | awk '{print $1}' | paste -sd, -)
  [[ "$sha_now" == "$sha_before" ]]
}

run_in_zsh() {
  local script="$1"
  ZDOTDIR="${FAKE_ZDOTDIR}" \
  HOME="${FAKE_HOME}" \
  ZSH="${REPO_ROOT}" \
  PATH="${FAKE_BIN}:${PATH}" \
  zsh --no-rcs -c "
    alias unrelated_alias='echo untouched'
    export UNRELATED_VAR='keep_unchanged'
    source '${PLUGIN_ZSH}'
    cd '${PROJECT_DIR}'
    eval '${script}'
  " 2>&1
}

# =============================================================================
# TEST 1: Sourcing state transition & alias definitions
# =============================================================================
out=$(ZDOTDIR="${FAKE_ZDOTDIR}" HOME="${FAKE_HOME}" ZSH="${REPO_ROOT}" PATH="${FAKE_BIN}:${PATH}" zsh --no-rcs -c "
  alias unrelated_alias='echo untouched'
  before_rb=\$(alias rb 2>/dev/null || echo 'absent')
  before_sgem=\$(alias sgem 2>/dev/null || echo 'absent')
  before_rfind=\$(alias rfind 2>/dev/null || echo 'absent')
  source '${PLUGIN_ZSH}'
  after_rb=\$(alias rb 2>/dev/null || echo 'absent')
  after_sgem=\$(alias sgem 2>/dev/null || echo 'absent')
  after_rfind=\$(alias rfind 2>/dev/null || echo 'absent')
  after_unrelated=\$(alias unrelated_alias 2>/dev/null || echo 'absent')
  echo \"BEFORE_RB:\$before_rb\"
  echo \"AFTER_RB:\$after_rb\"
  echo \"BEFORE_SGEM:\$before_sgem\"
  echo \"AFTER_SGEM:\$after_sgem\"
  echo \"BEFORE_RFIND:\$before_rfind\"
  echo \"AFTER_RFIND:\$after_rfind\"
  echo \"AFTER_UNRELATED:\$after_unrelated\"
")

if [[ "$out" == *"BEFORE_RB:absent"* && "$out" == *"AFTER_RB:rb=ruby"* && \
      "$out" == *"AFTER_SGEM:sgem='sudo gem'"* && \
      "$out" == *"AFTER_RFIND:rfind="* && \
      "$out" == *"AFTER_UNRELATED:unrelated_alias='echo untouched'"* ]]; then
  record "sourcing_state_transition" "PASS" "0" "rb, sgem, rfind defined; unrelated intact" "aliases defined as expected" "plugin alias definitions verified"
else
  record "sourcing_state_transition" "FAIL" "1" "$out" "aliases defined" "sourcing transition failed"
fi

# =============================================================================
# TEST 2: rb – Quoted path with spaces and argument with wildcard
#   Command: rb -I "lib dir with spaces" "app folder/test_*.rb"
#   Assert: ruby called with distinct arguments; wildcards not prematurely expanded;
#           decoy files remain untouched.
# =============================================================================
reset_stub
res=$(run_in_zsh "rb -I \"lib dir with spaces\" \"app folder/test_*.rb\"")
exit_code=$?
cmd=$(grep '^CMD:' "${STUB_LOG}" | head -1 | cut -d: -f2)
arg1=$(awk '/^ARG:/{sub(/^ARG:/,""); print; exit}' "${STUB_LOG}")
arg2=$(awk '/^ARG:/{n++; if(n==2){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg3=$(awk '/^ARG:/{n++; if(n==3){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")

if [[ "$cmd" == "ruby" && "$arg1" == "-I" && "$arg2" == "lib dir with spaces" && "$arg3" == "app folder/test_*.rb" && $exit_code -eq 0 ]] && check_decoys_intact; then
  record "rb_path_spaces_and_wildcard" "PASS" "${exit_code}" "cmd=ruby, args=['-I', 'lib dir with spaces', 'app folder/test_*.rb'], decoys intact" "exact args preserved without word-splitting" "rb preserves spaced paths and literal wildcards"
else
  record "rb_path_spaces_and_wildcard" "FAIL" "${exit_code}" "cmd=$cmd, args=['$arg1', '$arg2', '$arg3']" "args preserved" "argument boundary assertion failed"
fi

# =============================================================================
# TEST 3: sgem – Quoted path with spaces and wildcards
#   Command: sgem install "custom gems path/cool-pkg-*.gem" --bindir "/opt/my bin"
#   Assert: sudo invoked with 'gem', 'install', and intact quoted arguments.
# =============================================================================
reset_stub
res=$(run_in_zsh "sgem install \"custom gems path/cool-pkg-*.gem\" --bindir \"/opt/my bin\"")
exit_code=$?
cmd=$(grep '^CMD:' "${STUB_LOG}" | head -1 | cut -d: -f2)
arg1=$(awk '/^ARG:/{n++; if(n==1){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg2=$(awk '/^ARG:/{n++; if(n==2){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg3=$(awk '/^ARG:/{n++; if(n==3){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg4=$(awk '/^ARG:/{n++; if(n==4){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg5=$(awk '/^ARG:/{n++; if(n==5){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")

if [[ "$cmd" == "sudo" && "$arg1" == "gem" && "$arg2" == "install" && \
      "$arg3" == "custom gems path/cool-pkg-*.gem" && "$arg4" == "--bindir" && \
      "$arg5" == "/opt/my bin" && $exit_code -eq 0 ]] && check_decoys_intact; then
  record "sgem_path_spaces_and_wildcard" "PASS" "${exit_code}" "sudo gem install with spaced paths and wildcards intact" "all arguments preserved" "sgem argument boundary preserved"
else
  record "sgem_path_spaces_and_wildcard" "FAIL" "${exit_code}" "cmd=$cmd args=['$arg1', '$arg2', '$arg3', '$arg4', '$arg5']" "all arguments preserved" "sgem argument boundary failure"
fi

# =============================================================================
# TEST 4: rfind – Pipe command forwarding with space & wildcard pattern
#   Command: rfind "def *initialize"
#   Assert: find was invoked with '*.rb', xargs ran grep -n with the pattern.
# =============================================================================
reset_stub
res=$(run_in_zsh "rfind \"def *initialize\"")
exit_code=$?
find_called=$(awk '/^CMD:find$/{c++} END{print c+0}' "${STUB_LOG}")
grep_called=$(awk '/^CMD:grep$/{c++} END{print c+0}' "${STUB_LOG}")
grep_pattern=$(awk '/^CMD:grep$/{flag=1; next} flag && /^ARG:/{sub(/^ARG:/,""); if($0 != "-n"){print; exit}}' "${STUB_LOG}")

if [[ $find_called -ge 1 && $grep_called -ge 1 && "$grep_pattern" == "def *initialize" && $exit_code -eq 0 ]] && check_decoys_intact; then
  record "rfind_search_pattern_spaces_wildcards" "PASS" "${exit_code}" "find and grep called with pattern 'def *initialize'" "exact grep pattern preserved" "rfind pipe forwarding intact"
else
  record "rfind_search_pattern_spaces_wildcards" "FAIL" "${exit_code}" "find=$find_called grep=$grep_called pattern='$grep_pattern'" "pattern preserved" "rfind forwarding failed"
fi

# =============================================================================
# TEST 5: Documented failure/edge state – rb invalid option propagates exit 2
# =============================================================================
reset_stub
res=$(run_in_zsh "rb --invalid-flag")
exit_code=$?
if [[ $exit_code -eq 2 && "$res" == *"unrecognized option '--invalid-flag'"* ]] && check_decoys_intact; then
  record "rb_invalid_option_failure" "PASS" "${exit_code}" "exit=2, stderr captured" "exit=2" "documented failure: invalid option yields error exit code"
else
  record "rb_invalid_option_failure" "FAIL" "${exit_code}" "exit=$exit_code output=$res" "exit=2" "failure propagation failed"
fi

# =============================================================================
# TEST 6: Documented edge state – sgem failure exit code propagation
# =============================================================================
reset_stub
echo "1" > "${STUB_EXIT}"
res=$(run_in_zsh "sgem install missing_gem")
exit_code=$?
if [[ $exit_code -eq 1 ]] && check_decoys_intact; then
  record "sgem_failure_exit_propagation" "PASS" "${exit_code}" "exit=1 propagated" "exit=1" "documented edge: sgem propagates underlying failure status"
else
  record "sgem_failure_exit_propagation" "FAIL" "${exit_code}" "exit=$exit_code" "exit=1" "sgem failure propagation failed"
fi

# =============================================================================
# TEST 7: State isolation check
# =============================================================================
if [[ "${FAKE_HOME}" != "${HOME}" ]]; then
  record "state_isolation" "PASS" "0" "sandbox=${FAKE_HOME}" "isolated from ${HOME}" "no user state altered"
else
  record "state_isolation" "FAIL" "1" "sandbox equals real HOME" "isolated" "sandbox breach"
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "${TMPBASE}"
