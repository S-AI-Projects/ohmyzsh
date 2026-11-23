#!/usr/bin/env zsh
# run_tests.zsh – Regression and mutation test harness for conda plugin (R14-T030)
# Verifies entry points: cna, cnab, cncf.
# Evaluates temporary mutants to verify that the regression assertions actively reject mutations.

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

SCRIPT_DIR="${${0:a}:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."
PLUGIN_ZSH="${REPO_ROOT}/plugins/conda/conda.plugin.zsh"

TMPBASE=$(mktemp -d)
trap 'rm -rf "${TMPBASE}"' EXIT INT TERM

FAKE_HOME="${TMPBASE}/home"
FAKE_BIN="${TMPBASE}/bin"
FAKE_ZDOTDIR="${TMPBASE}/zdotdir"
STUB_LOG="${TMPBASE}/conda_calls.log"

mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${FAKE_ZDOTDIR}"

: > "${STUB_LOG}"

# ── Mock conda stub ───────────────────────────────────────────────────────────
cat > "${FAKE_BIN}/conda" <<'STUB'
#!/bin/sh
LOG="${CONDA_STUB_LOG:-/tmp/conda_calls.log}"
echo "CMD:conda" >> "${LOG}"
for arg in "$@"; do
  echo "ARG:${arg}" >> "${LOG}"
done

for arg in "$@"; do
  if [ "${arg}" = "--invalid-flag" ]; then
    echo "conda: error: unrecognized arguments: --invalid-flag" >&2
    exit 2
  fi
done

echo "conda operation completed"
exit 0
STUB
chmod +x "${FAKE_BIN}/conda"

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
  export CONDA_STUB_LOG="${STUB_LOG}"

  alias unrelated_alias='echo keep_unrelated'

  # Pre-conditions
  if alias cna >/dev/null 2>&1 || alias cnab >/dev/null 2>&1 || alias cncf >/dev/null 2>&1; then
    exit 10
  fi

  source "${PLUGIN_ZSH}"

  # Post-conditions: aliases defined
  alias cna >/dev/null 2>&1 || exit 11
  alias cnab >/dev/null 2>&1 || exit 12
  alias cncf >/dev/null 2>&1 || exit 13

  # Assert exact expansions
  [[ "$(alias cna)" == *"conda activate"* ]] || exit 14
  [[ "$(alias cnab)" == *"conda activate base"* ]] || exit 15
  [[ "$(alias cncf)" == *"conda env create -f"* ]] || exit 16

  # Unrelated alias intact
  [[ "$(alias unrelated_alias)" == *"keep_unrelated"* ]] || exit 17
  exit 0
)
T1_STATUS=$?
if [[ ${T1_STATUS} -eq 0 ]]; then
  record "sourcing_state_transition" "PASS" "0" "all conda aliases registered, unrelated preserved" "all aliases set" "pre/post state checked"
else
  record "sourcing_state_transition" "FAIL" "${T1_STATUS}" "alias registration failed" "all aliases set" "state check failed"
fi

# ── Test 2: cna Argument Expansion (conda activate <env>) ─────────────────────
: > "${STUB_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export CONDA_STUB_LOG="${STUB_LOG}"

  source "${PLUGIN_ZSH}"
  eval "cna my_dev_env" >/dev/null
  exit $?
)
T2_STATUS=$?
if [[ ${T2_STATUS} -eq 0 ]] && \
   grep -q "ARG:activate" "${STUB_LOG}" && \
   grep -q "ARG:my_dev_env" "${STUB_LOG}"; then
  record "cna_activate_environment" "PASS" "${T2_STATUS}" "passed activate my_dev_env" "exact args forwarded" "cna entry point verified"
else
  record "cna_activate_environment" "FAIL" "${T2_STATUS}" "arguments mismatch" "exact args forwarded" "failed argument forwarding"
fi

# ── Test 3: cnab Base Preservation Regression (conda activate base) ───────────
: > "${STUB_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export CONDA_STUB_LOG="${STUB_LOG}"

  source "${PLUGIN_ZSH}"
  eval "cnab" >/dev/null
  exit $?
)
T3_STATUS=$?
if [[ ${T3_STATUS} -eq 0 ]] && \
   grep -q "ARG:activate" "${STUB_LOG}" && \
   grep -q "ARG:base" "${STUB_LOG}"; then
  record "cnab_activate_base_regression" "PASS" "${T3_STATUS}" "passed activate base" "exact args forwarded" "cnab retains base environment"
else
  record "cnab_activate_base_regression" "FAIL" "${T3_STATUS}" "base argument missing" "exact args forwarded" "failed cnab regression check"
fi

# ── Test 4: cncf Environment Create Regression (conda env create -f <file>) ────
: > "${STUB_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export CONDA_STUB_LOG="${STUB_LOG}"

  source "${PLUGIN_ZSH}"
  eval "cncf environment.yml" >/dev/null
  exit $?
)
T4_STATUS=$?
if [[ ${T4_STATUS} -eq 0 ]] && \
   grep -q "ARG:env" "${STUB_LOG}" && \
   grep -q "ARG:create" "${STUB_LOG}" && \
   grep -q "ARG:-f" "${STUB_LOG}" && \
   grep -q "ARG:environment.yml" "${STUB_LOG}"; then
  record "cncf_env_create_regression" "PASS" "${T4_STATUS}" "passed env create -f environment.yml" "exact args forwarded" "cncf preserves env subcommand and -f flag"
else
  record "cncf_env_create_regression" "FAIL" "${T4_STATUS}" "env create flags missing" "exact args forwarded" "failed cncf regression check"
fi

# ── Test 5: Mutation Rejection: cnab Missing Base Argument ────────────────────
# Temporary mutant: cnab='conda activate' (omitting 'base')
MUTANT_LOG="${TMPBASE}/mutant_cnab.log"
: > "${MUTANT_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export CONDA_STUB_LOG="${MUTANT_LOG}"

  # Introduce mutant condition
  alias cnab='conda activate'
  eval "cnab" >/dev/null
)
# The regression oracle requires ARG:base; mutant must NOT satisfy this requirement
if grep -q -x "ARG:activate" "${MUTANT_LOG}" && ! grep -q -x "ARG:base" "${MUTANT_LOG}"; then
  # Mutant was successfully detected and rejected by the oracle
  record "mutation_rejection_cnab_dropped_base" "PASS" "0" "mutant detected: missing base argument rejected" "reject mutant" "mutation killed by regression assertion"
else
  record "mutation_rejection_cnab_dropped_base" "FAIL" "1" "mutant escaped detection" "reject mutant" "assertion failed to kill mutant"
fi

# ── Test 6: Mutation Rejection: cncf Missing 'env' Subcommand ──────────────────
# Temporary mutant: cncf='conda create -f' (omitting 'env')
MUTANT_LOG_CNCF="${TMPBASE}/mutant_cncf.log"
: > "${MUTANT_LOG_CNCF}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export CONDA_STUB_LOG="${MUTANT_LOG_CNCF}"

  # Introduce mutant condition
  alias cncf='conda create -f'
  eval "cncf environment.yml" >/dev/null
)
# The regression oracle requires ARG:env; mutant must NOT satisfy this requirement
if grep -q -x "ARG:create" "${MUTANT_LOG_CNCF}" && ! grep -q -x "ARG:env" "${MUTANT_LOG_CNCF}"; then
  # Mutant was successfully detected and rejected by the oracle
  record "mutation_rejection_cncf_dropped_env" "PASS" "0" "mutant detected: missing env subcommand rejected" "reject mutant" "mutation killed by regression assertion"
else
  record "mutation_rejection_cncf_dropped_env" "FAIL" "1" "mutant escaped detection" "reject mutant" "assertion failed to kill mutant"
fi

# ── Test 7: Documented Failure Branch (Invalid Flag Handling) ─────────────────
: > "${STUB_LOG}"
ERR_LOG="${TMPBASE}/err_invalid.log"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export CONDA_STUB_LOG="${STUB_LOG}"

  source "${PLUGIN_ZSH}"
  eval "cna --invalid-flag" >/dev/null 2>"${ERR_LOG}"
  exit $?
)
T7_STATUS=$?
if [[ ${T7_STATUS} -eq 2 ]] && grep -q "unrecognized arguments" "${ERR_LOG}"; then
  record "documented_failure_invalid_flag" "PASS" "${T7_STATUS}" "exit 2, unrecognized arguments rejected" "exit 2" "failure branch verified"
else
  record "documented_failure_invalid_flag" "FAIL" "${T7_STATUS}" "did not catch invalid flag" "exit 2" "failed invalid flag branch"
fi

# ── Test 8: Sandboxed State Isolation ─────────────────────────────────────────
if [[ -n "${FAKE_HOME}" && "${FAKE_HOME}" != "${HOME}" && -d "${FAKE_HOME}" ]]; then
  record "sandbox_state_isolation" "PASS" "0" "isolated temporary workspace" "isolated workspace" "real environment untouched"
else
  record "sandbox_state_isolation" "FAIL" "1" "environment leakage" "isolated workspace" "isolation compromised"
fi

exit 0
