#!/usr/bin/env zsh
# run_tests.zsh – Shell-side test harness for git-commit plugin (R14-T021)
# Runs inside a temporary ZDOTDIR/repo; never touches user git config or global state.
# Outputs structured lines consumed by check.py:
#   RESULT|<test-name>|<status>|<exit_code>|<actual_output>|<expected_output>|<notes>

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

# ── Locate the plugin root ────────────────────────────────────────────────────
PLUGIN_ROOT="${${0:a:h}/../..}"        # work/R14-T021 → repo root
PLUGIN_DIR="${PLUGIN_ROOT}/plugins/git-commit"
GIT_COMMANDS_DIR="${PLUGIN_DIR}/git-commands"

# ── Temporary sandbox ─────────────────────────────────────────────────────────
TMPBASE=$(mktemp -d)
FAKE_HOME="${TMPBASE}/home"
FAKE_GITREPO="${TMPBASE}/gitrepo"
FAKE_BIN="${TMPBASE}/bin"
RESULTS_FILE="${TMPBASE}/results.txt"

mkdir -p "${FAKE_HOME}" "${FAKE_GITREPO}" "${FAKE_BIN}"

# ── Stub `git commit` so we capture args without touching any real repo ───────
# The stub logs its argv (one per line, prefixed with ARG:) to a log file, then
# exits with the status stored in STUB_GIT_EXIT (default 0).
GIT_STUB_LOG="${TMPBASE}/git_stub.log"
GIT_STUB_EXIT_FILE="${TMPBASE}/git_stub_exit"
echo "0" > "${GIT_STUB_EXIT_FILE}"

cat > "${FAKE_BIN}/git" <<'STUB'
#!/bin/sh
EXIT_FILE="$(dirname "$0")/../git_stub_exit"
LOG_FILE="$(dirname "$0")/../git_stub.log"
EXIT_CODE=$(cat "${EXIT_FILE}" 2>/dev/null || echo 0)
printf 'ARG:%s\n' "$@" >> "${LOG_FILE}"
printf 'CALL\n' >> "${LOG_FILE}"
exit "${EXIT_CODE}"
STUB
chmod +x "${FAKE_BIN}/git"

# ── Helper: resolve absolute path of a git-commit script ─────────────────────
git_cmd() { echo "${GIT_COMMANDS_DIR}/git-$1"; }

# ── Helper: invoke a git-command script with a clean PATH ────────────────────
run_git_cmd() {
  local cmd_name="$1"; shift
  local cmd_path; cmd_path="$(git_cmd "${cmd_name}")"
  HOME="${FAKE_HOME}" \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_AUTHOR_NAME="Test" \
  GIT_AUTHOR_EMAIL="t@t.com" \
  GIT_COMMITTER_NAME="Test" \
  GIT_COMMITTER_EMAIL="t@t.com" \
  PATH="${FAKE_BIN}:${PATH}" \
    zsh "${cmd_path}" "$@" 2>&1
}

# ── Helper: record a test result ─────────────────────────────────────────────
record() {
  local name="$1" status="$2" exit_code="$3" actual="$4" expected="$5" notes="$6"
  printf 'RESULT|%s|%s|%s|%s|%s|%s\n' \
    "${name}" "${status}" "${exit_code}" "${actual}" "${expected}" "${notes}" \
    >> "${RESULTS_FILE}"
}

# ── Helper: clear the stub log between tests ─────────────────────────────────
reset_stub() {
  > "${GIT_STUB_LOG}"
  echo "0" > "${GIT_STUB_EXIT_FILE}"
}

# ── Helper: extract the -m value passed to git commit from the stub log ───────
extract_m_arg() {
  # Args are logged as ARG:-m then ARG:<value>
  awk '/^ARG:-m$/{getline; sub(/^ARG:/, ""); print; exit}' "${GIT_STUB_LOG}"
}

# =============================================================================
# TEST 1: Ordinary success – basic type only
#   git feat "add login page"  →  git commit -m "feat: add login page"
# =============================================================================
reset_stub
actual_output=$(run_git_cmd feat "add login page")
actual_exit=$?
commit_msg=$(extract_m_arg)
expected_msg="feat: add login page"
if [[ "${commit_msg}" == "${expected_msg}" && ${actual_exit} -eq 0 ]]; then
  record "basic_feat_success" "PASS" "${actual_exit}" "${commit_msg}" "${expected_msg}" "basic type, no scope"
else
  record "basic_feat_success" "FAIL" "${actual_exit}" "${commit_msg}" "${expected_msg}" "basic type, no scope"
fi

# =============================================================================
# TEST 2: Ordinary success – type with scope
#   git fix -s "router" "correct redirect"  →  "fix(router): correct redirect"
# =============================================================================
reset_stub
actual_output=$(run_git_cmd fix -s "router" "correct redirect")
actual_exit=$?
commit_msg=$(extract_m_arg)
expected_msg="fix(router): correct redirect"
if [[ "${commit_msg}" == "${expected_msg}" && ${actual_exit} -eq 0 ]]; then
  record "fix_with_scope" "PASS" "${actual_exit}" "${commit_msg}" "${expected_msg}" "type + scope"
else
  record "fix_with_scope" "FAIL" "${actual_exit}" "${commit_msg}" "${expected_msg}" "type + scope"
fi

# =============================================================================
# TEST 3: Ordinary success – attention flag (breaking change marker !)
#   git feat -a "break api"  →  "feat!: break api"
# =============================================================================
reset_stub
actual_output=$(run_git_cmd feat -a "break api")
actual_exit=$?
commit_msg=$(extract_m_arg)
expected_msg="feat!: break api"
if [[ "${commit_msg}" == "${expected_msg}" && ${actual_exit} -eq 0 ]]; then
  record "feat_attention_flag" "PASS" "${actual_exit}" "${commit_msg}" "${expected_msg}" "type + attention"
else
  record "feat_attention_flag" "FAIL" "${actual_exit}" "${commit_msg}" "${expected_msg}" "type + attention"
fi

# =============================================================================
# TEST 4: Ordinary success – rev alias maps to "revert"
#   git rev "rollback v2"  →  "revert: rollback v2"
# =============================================================================
reset_stub
actual_output=$(run_git_cmd rev "rollback v2")
actual_exit=$?
commit_msg=$(extract_m_arg)
expected_msg="revert: rollback v2"
if [[ "${commit_msg}" == "${expected_msg}" && ${actual_exit} -eq 0 ]]; then
  record "rev_maps_to_revert" "PASS" "${actual_exit}" "${commit_msg}" "${expected_msg}" "rev alias → revert type"
else
  record "rev_maps_to_revert" "FAIL" "${actual_exit}" "${commit_msg}" "${expected_msg}" "rev alias → revert type"
fi

# =============================================================================
# TEST 5: Ordinary success – scope + attention combined
#   git fix -s "api" -a "drop endpoint"  →  "fix(api)!: drop endpoint"
# =============================================================================
reset_stub
actual_output=$(run_git_cmd fix -s "api" -a "drop endpoint")
actual_exit=$?
commit_msg=$(extract_m_arg)
expected_msg="fix(api)!: drop endpoint"
if [[ "${commit_msg}" == "${expected_msg}" && ${actual_exit} -eq 0 ]]; then
  record "fix_scope_attention" "PASS" "${actual_exit}" "${commit_msg}" "${expected_msg}" "scope + attention"
else
  record "fix_scope_attention" "FAIL" "${actual_exit}" "${commit_msg}" "${expected_msg}" "scope + attention"
fi

# =============================================================================
# TEST 6: Edge / failure – missing scope value after -s flag
#   git feat -s  →  exit non-zero, stderr "Missing scope!"
# =============================================================================
reset_stub
actual_output=$(run_git_cmd feat -s 2>&1)
actual_exit=$?
# commit should NOT have been called
call_count=$(grep -c '^CALL$' "${GIT_STUB_LOG}" 2>/dev/null || echo 0)
expected_msg="Missing scope!"
if [[ ${actual_exit} -ne 0 && "${actual_output}" == *"Missing scope!"* && ${call_count} -eq 0 ]]; then
  record "missing_scope_value" "PASS" "${actual_exit}" "${actual_output}" "${expected_msg}" "edge: -s with no value"
else
  record "missing_scope_value" "FAIL" "${actual_exit}" "${actual_output}" "${expected_msg}" "edge: -s with no value; calls=${call_count}"
fi

# =============================================================================
# TEST 7: Edge – empty message string (positional, whitespace only)
#   git feat " "  →  commit still invoked; message is "feat:  " (space)
#   We document this behaviour (not a hard failure in current impl).
# =============================================================================
reset_stub
actual_output=$(run_git_cmd feat " ")
actual_exit=$?
commit_msg=$(extract_m_arg)
# Current implementation does commit with space-only message; we assert exit 0
# and that git was actually called (documents the existing empty-state behaviour).
call_count=$(grep -c '^CALL$' "${GIT_STUB_LOG}" 2>/dev/null || echo 0)
if [[ ${actual_exit} -eq 0 && ${call_count} -ge 1 ]]; then
  record "empty_message_whitespace" "PASS" "${actual_exit}" "git_called=${call_count} msg='${commit_msg}'" "git called with space msg" "documented: no empty-msg guard"
else
  record "empty_message_whitespace" "FAIL" "${actual_exit}" "git_called=${call_count} msg='${commit_msg}'" "git called with space msg" "documented: no empty-msg guard"
fi

# =============================================================================
# TEST 8: Edge – no arguments at all (missing message)
#   git feat  →  commit called with just "feat:" as message (no message text)
# =============================================================================
reset_stub
actual_output=$(run_git_cmd feat)
actual_exit=$?
commit_msg=$(extract_m_arg)
call_count=$(grep -c '^CALL$' "${GIT_STUB_LOG}" 2>/dev/null || echo 0)
# Document the state: git is called even without a message; message is "feat:"
if [[ ${call_count} -ge 1 ]]; then
  record "no_arguments_state" "PASS" "${actual_exit}" "git_called=${call_count} msg='${commit_msg}'" "git called, msg='feat:'" "documented: missing-message state"
else
  record "no_arguments_state" "FAIL" "${actual_exit}" "git_called=${call_count} msg='${commit_msg}'" "git called, msg='feat:'" "documented: missing-message state"
fi

# =============================================================================
# TEST 9: Verify plugin syntax check passes (native repo check)
# =============================================================================
zsh -n "${PLUGIN_DIR}/git-commit.plugin.zsh" 2>&1
zsh_n_exit=$?
if [[ ${zsh_n_exit} -eq 0 ]]; then
  record "plugin_syntax_check" "PASS" "${zsh_n_exit}" "zsh -n exit=0" "exit=0" "plugin file parses cleanly"
else
  record "plugin_syntax_check" "FAIL" "${zsh_n_exit}" "zsh -n exit=${zsh_n_exit}" "exit=0" "syntax error in plugin"
fi

# =============================================================================
# TEST 10: Verify git-commands scripts are executable
# =============================================================================
local_non_exec=()
for f in "${GIT_COMMANDS_DIR}"/git-*; do
  [[ -x "$f" ]] || local_non_exec+=("${f:t}")
done
if [[ ${#local_non_exec[@]} -eq 0 ]]; then
  record "git_commands_executable" "PASS" "0" "all scripts executable" "all scripts executable" ""
else
  record "git_commands_executable" "FAIL" "1" "not-exec: ${local_non_exec[*]}" "all scripts executable" ""
fi

# =============================================================================
# Output results file path for check.py to consume
# =============================================================================
echo "${RESULTS_FILE}"
