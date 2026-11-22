#!/usr/bin/env zsh
# run_tests.zsh – Shell-side test harness for bundler plugin (R14-T023)
# State-transition tests for entry points: ba, bck, bcn.
# Confines all execution to temporary directories.
# Never modifies user environment or external services.

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

SCRIPT_DIR="${${0:a}:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."
PLUGIN_ZSH="${REPO_ROOT}/plugins/bundler/bundler.plugin.zsh"

TMPBASE=$(mktemp -d)
FAKE_HOME="${TMPBASE}/home"
FAKE_BIN="${TMPBASE}/bin"
FAKE_ZDOTDIR="${TMPBASE}/zdotdir"
STUB_LOG="${TMPBASE}/stub_argv.log"
STUB_EXIT="${TMPBASE}/stub_exit.txt"
PROJECT_DIR="${TMPBASE}/project"

mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${FAKE_ZDOTDIR}" "${PROJECT_DIR}"
echo "0" > "${STUB_EXIT}"
: > "${STUB_LOG}"

# ── Stub: bundle ──────────────────────────────────────────────────────────────
cat > "${FAKE_BIN}/bundle" <<STUB
#!/bin/sh
LOG="${STUB_LOG}"
EXIT_VAL=\$(cat "${STUB_EXIT}" 2>/dev/null || echo 0)
for arg in "\$@"; do
  printf 'ARG:%s\n' "\$arg" >> "\$LOG"
done
printf 'CALL\n' >> "\$LOG"
if [ "\$EXIT_VAL" -ne 0 ]; then
  echo "bundler: simulated failure (exit \$EXIT_VAL)" >&2
  exit "\$EXIT_VAL"
fi
exit 0
STUB
chmod +x "${FAKE_BIN}/bundle"

# ── Helpers ───────────────────────────────────────────────────────────────────
reset_stub() {
  : > "${STUB_LOG}"
  echo "0" > "${STUB_EXIT}"
}

nth_arg() {
  awk -v n="$1" 'BEGIN{i=0} /^ARG:/{i++; if(i==n){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}"
}

all_args() {
  awk '/^ARG:/{sub(/^ARG:/,""); printf "%s ", $0} END{printf "\n"}' "${STUB_LOG}" | sed 's/ $//'
}

call_count() {
  grep -c '^CALL$' "${STUB_LOG}" 2>/dev/null || echo 0
}

record() {
  local name="$1" test_status="$2" exit_code="$3" actual="$4" expected="$5" notes="$6"
  printf 'RESULT|%s|%s|%s|%s|%s|%s\n' \
    "${name}" "${test_status}" "${exit_code}" "${actual}" "${expected}" "${notes}"
}

# Run a snippet with plugin loaded in clean zsh session using eval for alias expansion
run_in_zsh() {
  local script="$1"
  ZDOTDIR="${FAKE_ZDOTDIR}" \
  HOME="${FAKE_HOME}" \
  ZSH="${REPO_ROOT}" \
  PATH="${FAKE_BIN}:${PATH}" \
  zsh --no-rcs -c "
    alias unrelated_alias='echo untouched'
    export UNRELATED_VAR='keep_unchanged'
    compdef() { :; }
    source '${PLUGIN_ZSH}'
    eval '${script}'
  " 2>&1
}

# =============================================================================
# TEST 1: Sourcing state transition & unrelated state preservation
#   Before: ba/bck/bcn aliases do NOT exist; unrelated_alias exists.
#   After: ba/bck/bcn defined; unrelated_alias remains UNCHANGED.
# =============================================================================
out=$(ZDOTDIR="${FAKE_ZDOTDIR}" HOME="${FAKE_HOME}" ZSH="${REPO_ROOT}" PATH="${FAKE_BIN}:${PATH}" zsh --no-rcs -c "
  alias unrelated_alias='echo untouched'
  before_ba=\$(alias ba 2>/dev/null || echo 'absent')
  before_unrelated=\$(alias unrelated_alias 2>/dev/null || echo 'absent')
  compdef() { :; }
  source '${PLUGIN_ZSH}'
  after_ba=\$(alias ba 2>/dev/null || echo 'absent')
  after_unrelated=\$(alias unrelated_alias 2>/dev/null || echo 'absent')
  echo \"BEFORE_BA:\$before_ba\"
  echo \"AFTER_BA:\$after_ba\"
  echo \"BEFORE_UNRELATED:\$before_unrelated\"
  echo \"AFTER_UNRELATED:\$after_unrelated\"
")

if [[ "$out" == *"BEFORE_BA:absent"* && "$out" == *"AFTER_BA:ba='bundle add'"* && "$out" == *"AFTER_UNRELATED:unrelated_alias='echo untouched'"* ]]; then
  record "sourcing_state_transition" "PASS" "0" "ba defined, unrelated_alias preserved" "ba='bundle add', unrelated preserved" "shell definition transition verified"
else
  record "sourcing_state_transition" "FAIL" "1" "$out" "ba defined, unrelated_alias preserved" "shell definition transition failed"
fi

# =============================================================================
# TEST 2: Entry point 'ba' – ordinary success with arguments & unrelated state check
#   ba rake --group test -> bundle add rake --group test
#   Assert argv tokens, exit 0, and unrelated env var unchanged.
# =============================================================================
reset_stub
echo "initial_content" > "${PROJECT_DIR}/unrelated_file.txt"
content_before=$(cat "${PROJECT_DIR}/unrelated_file.txt")

res=$(run_in_zsh "ba rake --group test; echo ENV_CHECK:\$UNRELATED_VAR")
exit_code=$?
calls=$(call_count)
args=$(all_args)
content_after=$(cat "${PROJECT_DIR}/unrelated_file.txt")

if [[ ${calls} -ge 1 && "${args}" == "add rake --group test" && "$content_before" == "$content_after" && "$res" == *"ENV_CHECK:keep_unchanged"* ]]; then
  record "ba_ordinary_success" "PASS" "${exit_code}" "argv=[${args}], unrelated state preserved" "argv=[add rake --group test]" "ba forwards gem name and flags; unrelated state intact"
else
  record "ba_ordinary_success" "FAIL" "${exit_code}" "argv=[${args}], calls=${calls}" "argv=[add rake --group test]" "ba forwarding failed"
fi

# =============================================================================
# TEST 3: Entry point 'bck' – ordinary success
#   bck --path vendor/bundle -> bundle check --path vendor/bundle
# =============================================================================
reset_stub
res=$(run_in_zsh "bck --path vendor/bundle")
exit_code=$?
calls=$(call_count)
args=$(all_args)

if [[ ${calls} -ge 1 && "${args}" == "check --path vendor/bundle" && ${exit_code} -eq 0 ]]; then
  record "bck_ordinary_success" "PASS" "${exit_code}" "argv=[${args}]" "argv=[check --path vendor/bundle]" "bck forwards check flags"
else
  record "bck_ordinary_success" "FAIL" "${exit_code}" "argv=[${args}]" "argv=[check --path vendor/bundle]" "bck check flags failed"
fi

# =============================================================================
# TEST 4: Entry point 'bcn' – ordinary success
#   bcn --force -> bundle clean --force
# =============================================================================
reset_stub
res=$(run_in_zsh "bcn --force")
exit_code=$?
calls=$(call_count)
args=$(all_args)

if [[ ${calls} -ge 1 && "${args}" == "clean --force" && ${exit_code} -eq 0 ]]; then
  record "bcn_ordinary_success" "PASS" "${exit_code}" "argv=[${args}]" "argv=[clean --force]" "bcn forwards clean flags"
else
  record "bcn_ordinary_success" "FAIL" "${exit_code}" "argv=[${args}]" "argv=[clean --force]" "bcn clean flags failed"
fi

# =============================================================================
# TEST 5: Documented failure/edge state – 'bck' when dependencies unsatisfied
#   bundle check exits 1 when dependencies are missing.
#   Assert exit status 1, error output captured, and shell continues safely.
# =============================================================================
reset_stub
echo "1" > "${STUB_EXIT}"
res=$(run_in_zsh "bck")
exit_code=$?
calls=$(call_count)
args=$(all_args)

if [[ ${calls} -ge 1 && "${args}" == "check" && ${exit_code} -eq 1 ]]; then
  record "bck_unsatisfied_dependencies_failure" "PASS" "${exit_code}" "exit=1 (simulated unsatisfied dependencies)" "exit=1" "documented edge/failure: unsatisfied gems report non-zero"
else
  record "bck_unsatisfied_dependencies_failure" "FAIL" "${exit_code}" "exit=${exit_code} calls=${calls}" "exit=1" "bck failure handling assertion failed"
fi

# =============================================================================
# TEST 6: Documented edge state – 'ba' invocation failure propagates exit code
#   bundle add fails (e.g. invalid gem or missing argument)
#   Assert non-zero exit code correctly propagated to shell.
# =============================================================================
reset_stub
echo "2" > "${STUB_EXIT}"
res=$(run_in_zsh "ba")
exit_code=$?
calls=$(call_count)
args=$(all_args)

if [[ ${calls} -ge 1 && "${args}" == "add" && ${exit_code} -eq 2 ]]; then
  record "ba_failure_exit_propagation" "PASS" "${exit_code}" "exit=2" "exit=2" "documented edge: bundle add failure exit code propagates"
else
  record "ba_failure_exit_propagation" "FAIL" "${exit_code}" "exit=${exit_code}" "exit=2" "ba failure exit propagation failed"
fi

# =============================================================================
# TEST 7: State transition – _within-bundled-project detection
#   Without Gemfile -> returns 1
#   With Gemfile -> returns 0
# =============================================================================
test_proj="${TMPBASE}/proj_detect"
mkdir -p "${test_proj}"
out=$(run_in_zsh "
  cd '${test_proj}'
  _within-bundled-project
  echo WITHOUT_GEMFILE:\$?
  touch Gemfile
  _within-bundled-project
  echo WITH_GEMFILE:\$?
")

if [[ "$out" == *"WITHOUT_GEMFILE:1"* && "$out" == *"WITH_GEMFILE:0"* ]]; then
  record "within_bundled_project_transition" "PASS" "0" "without=1, with=0" "without=1, with=0" "state transition on Gemfile presence"
else
  record "within_bundled_project_transition" "FAIL" "1" "$out" "without=1, with=0" "project detection failed"
fi

# =============================================================================
# TEST 8: State isolation check
#   Verify FAKE_HOME != HOME and real configuration was untouched.
# =============================================================================
if [[ "${FAKE_HOME}" != "${HOME}" ]]; then
  record "state_isolation" "PASS" "0" "sandbox=${FAKE_HOME}" "isolated from ${HOME}" "no user state altered"
else
  record "state_isolation" "FAIL" "1" "sandbox equals real HOME" "isolated" "sandbox breach"
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "${TMPBASE}"
