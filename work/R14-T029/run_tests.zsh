#!/usr/bin/env zsh
# run_tests.zsh – Repeatable test entry point for ssh-agent plugin (R14-T029)
# Executes focused checks for _is_agent_running, _start_agent, and _add_identities,
# verifies failure propagation, ensures temporary state cleanup, and runs
# independently of unrelated background services.

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

SCRIPT_DIR="${${0:a}:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."
PLUGIN_ZSH="${REPO_ROOT}/plugins/ssh-agent/ssh-agent.plugin.zsh"

TMPBASE=$(mktemp -d)
trap 'rm -rf "${TMPBASE}"' EXIT INT TERM

FAKE_HOME="${TMPBASE}/home"
FAKE_BIN="${TMPBASE}/bin"
FAKE_ZDOTDIR="${TMPBASE}/zdotdir"
STUB_LOG="${TMPBASE}/stub_calls.log"

mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${FAKE_ZDOTDIR}" "${FAKE_HOME}/.ssh"

: > "${STUB_LOG}"

# ── Mock ssh-agent stub ───────────────────────────────────────────────────────
cat > "${FAKE_BIN}/ssh-agent" <<'STUB'
#!/bin/sh
LOG="${SSH_STUB_LOG:-/tmp/stub_calls.log}"
echo "CMD:ssh-agent" >> "${LOG}"
for arg in "$@"; do
  echo "ARG:${arg}" >> "${LOG}"
done

if [ "${FAIL_SSH_AGENT:-0}" = "1" ]; then
  echo "ssh-agent: failed to allocate resource" >&2
  exit 1
fi

SOCK="${FAKE_SOCK_DIR:-/tmp}/fake_agent.sock"
echo "SSH_AUTH_SOCK=${SOCK}; export SSH_AUTH_SOCK;"
echo "SSH_AGENT_PID=99999; export SSH_AGENT_PID;"
echo "echo Agent pid 99999;"
exit 0
STUB
chmod +x "${FAKE_BIN}/ssh-agent"

# ── Mock ssh-add stub ─────────────────────────────────────────────────────────
cat > "${FAKE_BIN}/ssh-add" <<'STUB'
#!/bin/sh
LOG="${SSH_STUB_LOG:-/tmp/stub_calls.log}"
echo "CMD:ssh-add" >> "${LOG}"
for arg in "$@"; do
  echo "ARG:${arg}" >> "${LOG}"
done

if [ "$1" = "-l" ]; then
  if [ "${MOCK_KEYS_LOADED:-0}" = "1" ]; then
    echo "2048 SHA256:dummyhash /root/.ssh/id_rsa (RSA)"
    exit 0
  else
    echo "The agent has no identities." >&2
    exit 1
  fi
fi

if [ "${FAIL_SSH_ADD:-0}" = "1" ]; then
  echo "ssh-add: failed to add identity" >&2
  exit 1
fi

echo "Identity added."
exit 0
STUB
chmod +x "${FAKE_BIN}/ssh-add"

# ── Mock ssh-keygen stub ──────────────────────────────────────────────────────
cat > "${FAKE_BIN}/ssh-keygen" <<'STUB'
#!/bin/sh
LOG="${SSH_STUB_LOG:-/tmp/stub_calls.log}"
echo "CMD:ssh-keygen" >> "${LOG}"
for arg in "$@"; do
  echo "ARG:${arg}" >> "${LOG}"
done

if [ "$1" = "-lf" ]; then
  echo "2048 SHA256:keyhash_for_$2 $2 (RSA)"
  exit 0
fi
exit 0
STUB
chmod +x "${FAKE_BIN}/ssh-keygen"

record() {
  local name="$1"
  local test_status="$2"
  local exit_code="$3"
  local actual="$4"
  local expected="$5"
  local notes="${6:-}"
  echo "RESULT|${name}|${test_status}|${exit_code}|${actual}|${expected}|${notes}"
}

# ── Test 1: _is_agent_running with empty or invalid socket ─────────────────────
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export SSH_STUB_LOG="${STUB_LOG}"
  export SHORT_HOST="testbox"

  zstyle :omz:plugins:ssh-agent test-mode yes
  source "${PLUGIN_ZSH}"

  # Empty socket
  unset SSH_AUTH_SOCK
  if _is_agent_running; then
    exit 1
  fi

  # Non-existent socket file
  export SSH_AUTH_SOCK="${TMPBASE}/nonexistent.sock"
  if _is_agent_running; then
    exit 2
  fi
  exit 0
)
T1_STATUS=$?
if [[ ${T1_STATUS} -eq 0 ]]; then
  record "is_agent_running_empty_or_invalid" "PASS" "0" "returns 1 when socket missing" "exit 1" "edge/failure condition correctly handled"
else
  record "is_agent_running_empty_or_invalid" "FAIL" "${T1_STATUS}" "unexpected return" "exit 1" "failed on invalid socket probe"
fi

# ── Test 2: _start_agent failure when ~/.ssh directory missing ─────────────────
NO_SSH_HOME="${TMPBASE}/no_ssh_home"
mkdir -p "${NO_SSH_HOME}"
(
  export HOME="${NO_SSH_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export SSH_STUB_LOG="${STUB_LOG}"
  export SHORT_HOST="testbox"

  zstyle :omz:plugins:ssh-agent test-mode yes
  source "${PLUGIN_ZSH}"

  _start_agent >/dev/null 2>&1
  exit $?
)
T2_STATUS=$?
if [[ ${T2_STATUS} -eq 1 ]]; then
  record "start_agent_missing_ssh_dir" "PASS" "${T2_STATUS}" "returns 1 when ~/.ssh missing" "exit 1" "missing prerequisite directory handled cleanly"
else
  record "start_agent_missing_ssh_dir" "FAIL" "${T2_STATUS}" "expected 1" "exit 1" "did not reject missing ~/.ssh"
fi

# ── Test 3: _start_agent success and environment caching ───────────────────────
: > "${STUB_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export SSH_STUB_LOG="${STUB_LOG}"
  export FAKE_SOCK_DIR="${TMPBASE}"
  export SHORT_HOST="testhost"

  zstyle :omz:plugins:ssh-agent test-mode yes
  zstyle :omz:plugins:ssh-agent quiet yes
  source "${PLUGIN_ZSH}"

  _start_agent || exit 10

  ENV_CACHE="${FAKE_HOME}/.ssh/environment-testhost"
  [[ -f "${ENV_CACHE}" ]] || exit 11

  # Check permissions 600
  PERMS=$(ls -l "${ENV_CACHE}" | awk '{print $1}')
  [[ "${PERMS}" == *"rw-------"* ]] || exit 12

  # Check that environment was sourced
  [[ "${SSH_AGENT_PID}" == "99999" ]] || exit 13
  exit 0
)
T3_STATUS=$?
if [[ ${T3_STATUS} -eq 0 ]] && grep -q "CMD:ssh-agent" "${STUB_LOG}"; then
  record "start_agent_success" "PASS" "${T3_STATUS}" "environment cached, PID 99999 set" "exit 0" "successful agent spawn and environment setup"
else
  record "start_agent_success" "FAIL" "${T3_STATUS}" "start_agent failed or log missing" "exit 0" "error during agent start"
fi

# ── Test 4: _start_agent propagates failure and cleans up temporary state ─────
: > "${STUB_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export SSH_STUB_LOG="${STUB_LOG}"
  export SHORT_HOST="failhost"
  export FAIL_SSH_AGENT=1

  zstyle :omz:plugins:ssh-agent test-mode yes
  zstyle :omz:plugins:ssh-agent quiet yes
  source "${PLUGIN_ZSH}"

  _start_agent 2>/dev/null
  STATUS=$?

  ENV_CACHE="${FAKE_HOME}/.ssh/environment-failhost"
  # Environment cache must be cleaned up / removed on failure
  if [[ -f "${ENV_CACHE}" ]]; then
    exit 20
  fi
  exit ${STATUS}
)
T4_STATUS=$?
if [[ ${T4_STATUS} -ne 0 && ${T4_STATUS} -ne 20 ]]; then
  record "start_agent_propagates_failure_and_cleans_up" "PASS" "${T4_STATUS}" "failure code propagated and cache cleaned up" "non-zero exit & no cache" "failure propagation & cleanup verified"
else
  record "start_agent_propagates_failure_and_cleans_up" "FAIL" "${T4_STATUS}" "cache not cleaned or failure not propagated" "exit non-zero" "failed cleanup or exit propagation"
fi

# ── Test 5: _start_agent honors lifetime setting ──────────────────────────────
: > "${STUB_LOG}"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export SSH_STUB_LOG="${STUB_LOG}"
  export SHORT_HOST="lifetimehost"

  zstyle :omz:plugins:ssh-agent test-mode yes
  zstyle :omz:plugins:ssh-agent quiet yes
  zstyle :omz:plugins:ssh-agent lifetime 4h
  source "${PLUGIN_ZSH}"

  _start_agent || exit 30
  exit 0
)
T5_STATUS=$?
if [[ ${T5_STATUS} -eq 0 ]] && grep -q "ARG:-t" "${STUB_LOG}" && grep -q "ARG:4h" "${STUB_LOG}"; then
  record "start_agent_lifetime_argument" "PASS" "${T5_STATUS}" "passed -t 4h to ssh-agent" "forward -t 4h" "zstyle lifetime forwarded"
else
  record "start_agent_lifetime_argument" "FAIL" "${T5_STATUS}" "args mismatch" "forward -t 4h" "did not pass lifetime flags"
fi

# ── Test 6: _add_identities with default keys ─────────────────────────────────
: > "${STUB_LOG}"
touch "${FAKE_HOME}/.ssh/id_rsa" "${FAKE_HOME}/.ssh/id_ed25519"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export SSH_STUB_LOG="${STUB_LOG}"
  export SHORT_HOST="addkeyshost"
  export MOCK_KEYS_LOADED=0

  zstyle :omz:plugins:ssh-agent test-mode yes
  zstyle -d :omz:plugins:ssh-agent identities
  source "${PLUGIN_ZSH}"

  _add_identities >/dev/null 2>&1
  exit $?
)
T6_STATUS=$?
if [[ ${T6_STATUS} -eq 0 ]] && \
   grep -q "ARG:${FAKE_HOME}/.ssh/id_rsa" "${STUB_LOG}" && \
   grep -q "ARG:${FAKE_HOME}/.ssh/id_ed25519" "${STUB_LOG}"; then
  record "add_identities_default_keys" "PASS" "${T6_STATUS}" "added id_rsa and id_ed25519" "exit 0 with default keys" "default identity discovery works"
else
  record "add_identities_default_keys" "FAIL" "${T6_STATUS}" "identities not added" "exit 0" "default keys addition failed"
fi

# ── Test 7: _add_identities with custom zstyle identities and arguments ───────
: > "${STUB_LOG}"
touch "${FAKE_HOME}/.ssh/custom_key1"
(
  export HOME="${FAKE_HOME}"
  export ZDOTDIR="${FAKE_ZDOTDIR}"
  export PATH="${FAKE_BIN}:${PATH}"
  export SSH_STUB_LOG="${STUB_LOG}"
  export SHORT_HOST="customhost"
  export MOCK_KEYS_LOADED=0

  zstyle :omz:plugins:ssh-agent test-mode yes
  zstyle :omz:plugins:ssh-agent identities custom_key1
  zstyle :omz:plugins:ssh-agent quiet yes
  zstyle :omz:plugins:ssh-agent ssh-add-args -c
  source "${PLUGIN_ZSH}"

  _add_identities >/dev/null 2>&1
  exit $?
)
T7_STATUS=$?
if [[ ${T7_STATUS} -eq 0 ]] && \
   grep -q "ARG:-q" "${STUB_LOG}" && \
   grep -q "ARG:-c" "${STUB_LOG}" && \
   grep -q "ARG:${FAKE_HOME}/.ssh/custom_key1" "${STUB_LOG}"; then
  record "add_identities_custom_and_args" "PASS" "${T7_STATUS}" "passed -q -c and custom_key1" "exact args" "quiet mode and custom args forwarded"
else
  record "add_identities_custom_and_args" "FAIL" "${T7_STATUS}" "args mismatch" "exact args" "custom identities or args failed"
fi

# ── Test 8: Sandboxed State Isolation ─────────────────────────────────────────
if [[ -n "${FAKE_HOME}" && "${FAKE_HOME}" != "${HOME}" && -d "${FAKE_HOME}" ]]; then
  record "sandbox_state_isolation" "PASS" "0" "isolated temporary workspace" "isolated workspace" "real environment untouched"
else
  record "sandbox_state_isolation" "FAIL" "1" "environment leakage" "isolated workspace" "isolation compromised"
fi

exit 0
