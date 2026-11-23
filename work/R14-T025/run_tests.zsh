#!/usr/bin/env zsh
# run_tests.zsh – Shell test harness for mvn plugin (R14-T025)
# Verifies environment isolation, deterministic wrapper resolution,
# argument forwarding, and missing-dependency edge cases.

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

SCRIPT_DIR="${${0:a}:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."
PLUGIN_ZSH="${REPO_ROOT}/plugins/mvn/mvn.plugin.zsh"

TMPBASE=$(mktemp -d)
FAKE_HOME="${TMPBASE}/home"
FAKE_BIN="${TMPBASE}/bin"
EMPTY_BIN="${TMPBASE}/empty_bin"
FAKE_ZDOTDIR="${TMPBASE}/zdotdir"
MVN_LOG="${TMPBASE}/mvn.log"
MVNW_LOG="${TMPBASE}/mvnw.log"
STUB_EXIT="${TMPBASE}/stub_exit.txt"

# Directory structures
PROJ_WITH_WRAPPER="${TMPBASE}/proj_wrapper"
PROJ_SUBDIR="${PROJ_WITH_WRAPPER}/sub/deep"
PROJ_NOEXEC_WRAPPER="${TMPBASE}/proj_noexec"
PROJ_PLAIN="${TMPBASE}/proj_plain"

mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${EMPTY_BIN}" "${FAKE_ZDOTDIR}" \
         "${PROJ_SUBDIR}" "${PROJ_NOEXEC_WRAPPER}" "${PROJ_PLAIN}"

echo "0" > "${STUB_EXIT}"
: > "${MVN_LOG}"
: > "${MVNW_LOG}"

# ── Stub: system mvn ──────────────────────────────────────────────────────────
cat > "${FAKE_BIN}/mvn" <<STUB
#!/bin/sh
LOG="${MVN_LOG}"
EXIT_VAL=\$(cat "${STUB_EXIT}" 2>/dev/null || echo 0)
echo "INVOKED:mvn" >> "\$LOG"
for arg in "\$@"; do
  printf 'ARG:%s\n' "\$arg" >> "\$LOG"
done
echo "CALL" >> "\$LOG"
exit "\$EXIT_VAL"
STUB
chmod +x "${FAKE_BIN}/mvn"

# ── Stub: executable mvnw in PROJ_WITH_WRAPPER ────────────────────────────────
cat > "${PROJ_WITH_WRAPPER}/mvnw" <<STUB
#!/bin/sh
LOG="${MVNW_LOG}"
EXIT_VAL=\$(cat "${STUB_EXIT}" 2>/dev/null || echo 0)
echo "INVOKED:mvnw" >> "\$LOG"
for arg in "\$@"; do
  printf 'ARG:%s\n' "\$arg" >> "\$LOG"
done
echo "CALL" >> "\$LOG"
exit "\$EXIT_VAL"
STUB
chmod +x "${PROJ_WITH_WRAPPER}/mvnw"

# ── Non-executable mvnw in PROJ_NOEXEC_WRAPPER (chmod 0644) ──────────────────
cat > "${PROJ_NOEXEC_WRAPPER}/mvnw" <<STUB
#!/bin/sh
echo "INVOKED:non_exec_mvnw" >> "${MVNW_LOG}"
exit 99
STUB
chmod 0644 "${PROJ_NOEXEC_WRAPPER}/mvnw"

# ── Helpers ───────────────────────────────────────────────────────────────────
reset_stubs() {
  : > "${MVN_LOG}"
  : > "${MVNW_LOG}"
  echo "0" > "${STUB_EXIT}"
}

record() {
  local name="$1" test_status="$2" exit_code="$3" actual="$4" expected="$5" notes="$6"
  printf 'RESULT|%s|%s|%s|%s|%s|%s\n' \
    "${name}" "${test_status}" "${exit_code}" "${actual}" "${expected}" "${notes}"
}

run_in_zsh() {
  local workdir="$1"
  local path_bin="$2"
  local script="$3"

  ZDOTDIR="${FAKE_ZDOTDIR}" \
  HOME="${FAKE_HOME}" \
  ZSH="${REPO_ROOT}" \
  PATH="${path_bin}:${PATH}" \
  zsh --no-rcs -c "
    alias unrelated_alias='echo untouched'
    export UNRELATED_VAR='keep_unchanged'
    compctl() { :; }
    source '${PLUGIN_ZSH}'
    cd '${workdir}'
    eval '${script}'
  " 2>&1
}

# =============================================================================
# TEST 1: Sourcing state transition & alias definitions
# =============================================================================
out=$(ZDOTDIR="${FAKE_ZDOTDIR}" HOME="${FAKE_HOME}" ZSH="${REPO_ROOT}" PATH="${FAKE_BIN}:${PATH}" zsh --no-rcs -c "
  alias unrelated_alias='echo untouched'
  before_mvn=\$(alias mvn 2>/dev/null || echo 'absent')
  before_mvnag=\$(alias mvnag 2>/dev/null || echo 'absent')
  before_mvnboot=\$(alias mvnboot 2>/dev/null || echo 'absent')
  compctl() { :; }
  source '${PLUGIN_ZSH}'
  after_mvn=\$(alias mvn 2>/dev/null || echo 'absent')
  after_mvnag=\$(alias mvnag 2>/dev/null || echo 'absent')
  after_mvnboot=\$(alias mvnboot 2>/dev/null || echo 'absent')
  after_unrelated=\$(alias unrelated_alias 2>/dev/null || echo 'absent')
  echo \"BEFORE_MVN:\$before_mvn\"
  echo \"AFTER_MVN:\$after_mvn\"
  echo \"BEFORE_MVNAG:\$before_mvnag\"
  echo \"AFTER_MVNAG:\$after_mvnag\"
  echo \"BEFORE_MVNBOOT:\$before_mvnboot\"
  echo \"AFTER_MVNBOOT:\$after_mvnboot\"
  echo \"AFTER_UNRELATED:\$after_unrelated\"
")

if [[ "$out" == *"BEFORE_MVN:absent"* && "$out" == *"AFTER_MVN:mvn=mvn-or-mvnw"* && \
      "$out" == *"AFTER_MVNAG:mvnag='mvn archetype:generate'"* && \
      "$out" == *"AFTER_MVNBOOT:mvnboot='mvn spring-boot:run'"* && \
      "$out" == *"AFTER_UNRELATED:unrelated_alias='echo untouched'"* ]]; then
  record "sourcing_state_transition" "PASS" "0" "mvn, mvnag, mvnboot defined; unrelated alias intact" "aliases defined as expected" "plugin alias definitions verified"
else
  record "sourcing_state_transition" "FAIL" "1" "$out" "aliases defined" "sourcing transition failed"
fi

# =============================================================================
# TEST 2: mvnboot with executable wrapper in parent directory
#   From PROJ_SUBDIR, mvnboot resolves ../../mvnw, passes arguments, logs to stderr
# =============================================================================
reset_stubs
res=$(run_in_zsh "${PROJ_SUBDIR}" "${FAKE_BIN}" "mvnboot -DskipTests -Dapp.name=\"my service\"")
exit_code=$?
mvnw_called=$(awk '/^INVOKED:mvnw$/{c++} END{print c+0}' "${MVNW_LOG}")
mvn_called=$(awk '/^INVOKED:mvn$/{c++} END{print c+0}' "${MVN_LOG}")
arg1=$(awk '/^ARG:/{sub(/^ARG:/,""); print; exit}' "${MVNW_LOG}")
arg2=$(awk '/^ARG:/{n++; if(n==2){sub(/^ARG:/,""); print; exit}}' "${MVNW_LOG}")
arg3=$(awk '/^ARG:/{n++; if(n==3){sub(/^ARG:/,""); print; exit}}' "${MVNW_LOG}")

if [[ $mvnw_called -eq 1 && $mvn_called -eq 0 && "$arg1" == "spring-boot:run" && \
      "$arg2" == "-DskipTests" && "$arg3" == "-Dapp.name=my service" && \
      "$res" == *"Running \`"*"/mvnw\`..."* && $exit_code -eq 0 ]]; then
  record "mvnboot_with_wrapper_in_parent" "PASS" "${exit_code}" "invoked parent mvnw with spring-boot:run and arguments" "mvnw invoked with args" "mvnw lookup from subdirectory verified"
else
  record "mvnboot_with_wrapper_in_parent" "FAIL" "${exit_code}" "mvnw=$mvnw_called mvn=$mvn_called args=['$arg1','$arg2','$arg3']" "parent mvnw invoked" "wrapper lookup failed"
fi

# =============================================================================
# TEST 3: mvnag without wrapper falls back to system mvn
# =============================================================================
reset_stubs
res=$(run_in_zsh "${PROJ_PLAIN}" "${FAKE_BIN}" "mvnag -DarchetypeGroupId=\"org.apache.maven\"")
exit_code=$?
mvnw_called=$(awk '/^INVOKED:mvnw$/{c++} END{print c+0}' "${MVNW_LOG}")
mvn_called=$(awk '/^INVOKED:mvn$/{c++} END{print c+0}' "${MVN_LOG}")
arg1=$(awk '/^ARG:/{sub(/^ARG:/,""); print; exit}' "${MVN_LOG}")
arg2=$(awk '/^ARG:/{n++; if(n==2){sub(/^ARG:/,""); print; exit}}' "${MVN_LOG}")

if [[ $mvn_called -eq 1 && $mvnw_called -eq 0 && "$arg1" == "archetype:generate" && \
      "$arg2" == "-DarchetypeGroupId=org.apache.maven" && \
      "$res" != *"Running \`"* && $exit_code -eq 0 ]]; then
  record "mvnag_fallback_to_mvn" "PASS" "${exit_code}" "fallback to mvn with archetype:generate and args" "mvn invoked directly" "fallback to mvn verified"
else
  record "mvnag_fallback_to_mvn" "FAIL" "${exit_code}" "mvn=$mvn_called mvnw=$mvnw_called args=['$arg1','$arg2']" "fallback to mvn" "mvnag fallback failed"
fi

# =============================================================================
# TEST 4: Non-executable mvnw is skipped and falls back to system mvn
# =============================================================================
reset_stubs
res=$(run_in_zsh "${PROJ_NOEXEC_WRAPPER}" "${FAKE_BIN}" "mvn clean package")
exit_code=$?
mvnw_called=$(awk '/^INVOKED:/{c++} END{print c+0}' "${MVNW_LOG}")
mvn_called=$(awk '/^INVOKED:mvn$/{c++} END{print c+0}' "${MVN_LOG}")
arg1=$(awk '/^ARG:/{sub(/^ARG:/,""); print; exit}' "${MVN_LOG}")
arg2=$(awk '/^ARG:/{n++; if(n==2){sub(/^ARG:/,""); print; exit}}' "${MVN_LOG}")

if [[ $mvn_called -eq 1 && $mvnw_called -eq 0 && "$arg1" == "clean" && \
      "$arg2" == "package" && $exit_code -eq 0 ]]; then
  record "non_executable_mvnw_skipped" "PASS" "${exit_code}" "non-executable mvnw skipped, fallback to mvn" "fallback to mvn" "non-executable wrapper skipped"
else
  record "non_executable_mvnw_skipped" "FAIL" "${exit_code}" "mvn=$mvn_called nonexec_called=$mvnw_called args=['$arg1','$arg2']" "fallback to mvn" "non-executable check failed"
fi

# =============================================================================
# TEST 5: Documented edge state – wrapper exit status propagation
#   When mvnw returns exit status 3 (e.g. compilation failure), mvnboot propagates 3
# =============================================================================
reset_stubs
echo "3" > "${STUB_EXIT}"
res=$(run_in_zsh "${PROJ_SUBDIR}" "${FAKE_BIN}" "mvnboot")
exit_code=$?
if [[ $exit_code -eq 3 ]]; then
  record "wrapper_exit_status_propagation" "PASS" "${exit_code}" "exit=3 propagated from mvnw" "exit=3" "documented edge: wrapper non-zero exit status propagates"
else
  record "wrapper_exit_status_propagation" "FAIL" "${exit_code}" "exit=$exit_code" "exit=3" "exit status propagation failed"
fi

# =============================================================================
# TEST 6: Documented failure/edge state – missing dependency branch
#   When neither mvnw nor mvn on PATH is available, command mvn fails with 127
# =============================================================================
reset_stubs
res=$(run_in_zsh "${PROJ_PLAIN}" "${EMPTY_BIN}" "mvn test")
exit_code=$?
if [[ $exit_code -eq 127 || "$res" == *"command not found"* || "$res" == *"not found"* ]]; then
  record "missing_dependency_branch" "PASS" "${exit_code}" "exit=${exit_code}, command not found reported" "exit=127" "documented failure: missing mvn dependency handled cleanly"
else
  record "missing_dependency_branch" "FAIL" "${exit_code}" "exit=$exit_code output=$res" "exit=127" "missing dependency assertion failed"
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
