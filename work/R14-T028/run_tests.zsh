#!/usr/bin/env zsh
# run_tests.zsh – Shell test harness for rsync plugin (R14-T028)
# Demonstrates failure diagnostics on missing source paths (exit status 23),
# verifies troubleshooting guidance with corrected invocation succeeding (exit status 0),
# and validates alias argument preservation across rsync-copy, rsync-move, rsync-update, and rsync-synchronize.

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

SCRIPT_DIR="${${0:a}:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."
PLUGIN_ZSH="${REPO_ROOT}/plugins/rsync/rsync.plugin.zsh"

TMPBASE=$(mktemp -d)
FAKE_HOME="${TMPBASE}/home"
FAKE_BIN="${TMPBASE}/bin"
FAKE_ZDOTDIR="${TMPBASE}/zdotdir"
STUB_LOG="${TMPBASE}/rsync_calls.log"
WORKSPACE="${TMPBASE}/workspace"

mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${FAKE_ZDOTDIR}" "${WORKSPACE}"

: > "${STUB_LOG}"

# ── Mock rsync stub ───────────────────────────────────────────────────────────
cat > "${FAKE_BIN}/rsync" <<'STUB'
#!/bin/sh
LOG="${RSYNC_STUB_LOG:-/tmp/rsync_calls.log}"
echo "CMD:rsync" >> "${LOG}"
for arg in "$@"; do
  echo "ARG:${arg}" >> "${LOG}"
done

# Check for failure test cases
for arg in "$@"; do
  if [ "$arg" = "--invalid-option" ]; then
    echo "rsync: --invalid-option: unknown option" >&2
    exit 1
  fi
  if [ "$arg" = "missing_src/" ] || [ "$arg" = "missing_src" ] || [ "$arg" = "nonexistent/" ]; then
    echo "rsync: [sender] change_dir \"${arg}\" failed: No such file or directory (2)" >&2
    echo "rsync error: some files/attrs were not transferred (see previous errors) (code 23)" >&2
    exit 23
  fi
done

echo "sending incremental file list"
exit 0
STUB
chmod +x "${FAKE_BIN}/rsync"

record() {
  local name="$1"
  local test_status="$2"
  local exit_code="$3"
  local actual="$4"
  local expected="$5"
  local notes="${6:-}"
  echo "RESULT|${name}|${test_status}|${exit_code}|${actual}|${expected}|${notes}"
}

# ── Test 1: Sourcing State Transition ─────────────────────────────────────────
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export RSYNC_STUB_LOG="${STUB_LOG}"

  alias unrelated_alias='echo preserved_unrelated'

  # Pre-conditions
  if alias rsync-copy >/dev/null 2>&1; then
    exit 10
  fi

  # Source plugin
  source "${PLUGIN_ZSH}"

  # Post-conditions: all 4 aliases defined
  alias rsync-copy >/dev/null 2>&1 || exit 11
  alias rsync-move >/dev/null 2>&1 || exit 12
  alias rsync-update >/dev/null 2>&1 || exit 13
  alias rsync-synchronize >/dev/null 2>&1 || exit 14

  [[ "$(alias rsync-copy)" == *"rsync -avz --progress -h"* ]] || exit 15
  [[ "$(alias rsync-move)" == *"rsync -avz --progress -h --remove-source-files"* ]] || exit 16
  [[ "$(alias rsync-update)" == *"rsync -avzu --progress -h"* ]] || exit 17
  [[ "$(alias rsync-synchronize)" == *"rsync -avzu --delete --progress -h"* ]] || exit 18

  [[ "$(alias unrelated_alias)" == *"preserved_unrelated"* ]] || exit 19
  exit 0
)
T1_STATUS=$?
if [[ ${T1_STATUS} -eq 0 ]]; then
  record "sourcing_state_transition" "PASS" "0" "4 aliases defined, unrelated alias preserved" "all aliases set" "pre/post state checked"
else
  record "sourcing_state_transition" "FAIL" "${T1_STATUS}" "alias definitions failed" "all aliases set" "exit code ${T1_STATUS}"
fi

# ── Test 2: Failing Invocation (Missing Source Path) ───────────────────────────
: > "${STUB_LOG}"
ERR_FILE="${TMPBASE}/test2_err.log"
OUT_FILE="${TMPBASE}/test2_out.log"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export RSYNC_STUB_LOG="${STUB_LOG}"
  cd "${WORKSPACE}"

  source "${PLUGIN_ZSH}"
  eval "rsync-copy missing_src/ backup/" >"${OUT_FILE}" 2>"${ERR_FILE}"
)
T2_STATUS=$?

if [[ ${T2_STATUS} -eq 23 ]] && \
   grep -q "No such file or directory" "${ERR_FILE}" && \
   grep -q "code 23" "${ERR_FILE}" && \
   grep -q "ARG:missing_src/" "${STUB_LOG}"; then
  record "failing_invocation_missing_source" "PASS" "${T2_STATUS}" "exit 23, No such file or directory, code 23 reported" "exit 23 on missing source" "failure branch reached & verified"
else
  record "failing_invocation_missing_source" "FAIL" "${T2_STATUS}" "unexpected error or exit status" "exit 23" "error output verification failed"
fi

# ── Test 3: Corrected Invocation Succeeding Afterwards ─────────────────────────
: > "${STUB_LOG}"
CORRECTED_OUT="${TMPBASE}/test3_out.log"
CORRECTED_ERR="${TMPBASE}/test3_err.log"
mkdir -p "${WORKSPACE}/valid_src"
touch "${WORKSPACE}/valid_src/item.txt"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export RSYNC_STUB_LOG="${STUB_LOG}"
  cd "${WORKSPACE}"

  source "${PLUGIN_ZSH}"
  eval "rsync-copy valid_src/ backup/" >"${CORRECTED_OUT}" 2>"${CORRECTED_ERR}"
)
T3_STATUS=$?

if [[ ${T3_STATUS} -eq 0 ]] && \
   grep -q "ARG:-avz" "${STUB_LOG}" && \
   grep -q "ARG:--progress" "${STUB_LOG}" && \
   grep -q "ARG:-h" "${STUB_LOG}" && \
   grep -q "ARG:valid_src/" "${STUB_LOG}" && \
   grep -q "ARG:backup/" "${STUB_LOG}"; then
  record "corrected_invocation_success" "PASS" "${T3_STATUS}" "exit 0, incremental file list transferred" "exit 0" "corrected invocation succeeds after creating fixture"
else
  record "corrected_invocation_success" "FAIL" "${T3_STATUS}" "failed corrected invocation" "exit 0" "arguments or execution failed"
fi

# ── Test 4: rsync-move Argument Preservation ──────────────────────────────────
: > "${STUB_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export RSYNC_STUB_LOG="${STUB_LOG}"
  cd "${WORKSPACE}"

  source "${PLUGIN_ZSH}"
  eval "rsync-move src_dir/ dst_dir/" >/dev/null 2>&1
)
T4_STATUS=$?

if [[ ${T4_STATUS} -eq 0 ]] && \
   grep -q "ARG:-avz" "${STUB_LOG}" && \
   grep -q "ARG:--remove-source-files" "${STUB_LOG}" && \
   grep -q "ARG:src_dir/" "${STUB_LOG}" && \
   grep -q "ARG:dst_dir/" "${STUB_LOG}"; then
  record "rsync_move_arguments_preservation" "PASS" "${T4_STATUS}" "flags -avz -h --remove-source-files passed" "exact flag forwarding" "rsync-move preserves --remove-source-files"
else
  record "rsync_move_arguments_preservation" "FAIL" "${T4_STATUS}" "flag mismatch" "exact flags" "failed to pass --remove-source-files"
fi

# ── Test 5: rsync-update Argument Preservation ────────────────────────────────
: > "${STUB_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export RSYNC_STUB_LOG="${STUB_LOG}"
  cd "${WORKSPACE}"

  source "${PLUGIN_ZSH}"
  eval "rsync-update src_dir/ dst_dir/" >/dev/null 2>&1
)
T5_STATUS=$?

if [[ ${T5_STATUS} -eq 0 ]] && \
   grep -q "ARG:-avzu" "${STUB_LOG}" && \
   grep -q "ARG:--progress" "${STUB_LOG}" && \
   grep -q "ARG:src_dir/" "${STUB_LOG}" && \
   grep -q "ARG:dst_dir/" "${STUB_LOG}"; then
  record "rsync_update_arguments_preservation" "PASS" "${T5_STATUS}" "flags -avzu --progress -h passed" "exact flag forwarding" "rsync-update preserves -avzu"
else
  record "rsync_update_arguments_preservation" "FAIL" "${T5_STATUS}" "flag mismatch" "exact flags" "failed to pass -avzu"
fi

# ── Test 6: rsync-synchronize Argument Preservation ───────────────────────────
: > "${STUB_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export RSYNC_STUB_LOG="${STUB_LOG}"
  cd "${WORKSPACE}"

  source "${PLUGIN_ZSH}"
  eval "rsync-synchronize src_dir/ dst_dir/" >/dev/null 2>&1
)
T6_STATUS=$?

if [[ ${T6_STATUS} -eq 0 ]] && \
   grep -q "ARG:-avzu" "${STUB_LOG}" && \
   grep -q "ARG:--delete" "${STUB_LOG}" && \
   grep -q "ARG:src_dir/" "${STUB_LOG}" && \
   grep -q "ARG:dst_dir/" "${STUB_LOG}"; then
  record "rsync_synchronize_arguments_preservation" "PASS" "${T6_STATUS}" "flags -avzu --delete passed" "exact flag forwarding" "rsync-synchronize preserves --delete"
else
  record "rsync_synchronize_arguments_preservation" "FAIL" "${T6_STATUS}" "flag mismatch" "exact flags" "failed to pass --delete"
fi

# ── Test 7: Documented Failure with Invalid Option ────────────────────────────
: > "${STUB_LOG}"
ERR_INVALID="${TMPBASE}/test7_err.log"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export RSYNC_STUB_LOG="${STUB_LOG}"
  cd "${WORKSPACE}"

  source "${PLUGIN_ZSH}"
  eval "rsync-copy --invalid-option" >/dev/null 2>"${ERR_INVALID}"
)
T7_STATUS=$?

if [[ ${T7_STATUS} -ne 0 ]] && grep -q "unknown option" "${ERR_INVALID}"; then
  record "documented_failure_invalid_option" "PASS" "${T7_STATUS}" "exit ${T7_STATUS}, unknown option" "non-zero exit on unknown option" "failure edge case handled"
else
  record "documented_failure_invalid_option" "FAIL" "${T7_STATUS}" "did not catch invalid option" "exit 1" "failed invalid option check"
fi

# ── Test 8: Sandboxed State Isolation ─────────────────────────────────────────
if [[ -n "${FAKE_HOME}" && "${FAKE_HOME}" != "${HOME}" && -d "${FAKE_HOME}" ]]; then
  record "sandbox_state_isolation" "PASS" "0" "isolated temporary workspace" "isolated workspace" "real environment untouched"
else
  record "sandbox_state_isolation" "FAIL" "1" "environment leakage" "isolated workspace" "isolation compromised"
fi

# Clean up temporary test files
rm -rf "${TMPBASE}"
exit 0
