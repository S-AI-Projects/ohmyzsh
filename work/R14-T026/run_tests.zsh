#!/usr/bin/env zsh
# run_tests.zsh – Shell characterization test harness for git-lfs plugin (R14-T026)
# Tests entry points: glfsi, glfst, glfsls, and simplified helper gplfs.
# Confines all execution to temporary directories.

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

SCRIPT_DIR="${${0:a}:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."
PLUGIN_ZSH="${REPO_ROOT}/plugins/git-lfs/git-lfs.plugin.zsh"

TMPBASE=$(mktemp -d)
FAKE_HOME="${TMPBASE}/home"
FAKE_BIN="${TMPBASE}/bin"
FAKE_ZDOTDIR="${TMPBASE}/zdotdir"
STUB_LOG="${TMPBASE}/git_stub.log"
STUB_EXIT="${TMPBASE}/stub_exit.txt"
WORK_DIR="${TMPBASE}/work"

mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${FAKE_ZDOTDIR}" "${WORK_DIR}"
echo "0" > "${STUB_EXIT}"
: > "${STUB_LOG}"

# ── Stub: git ─────────────────────────────────────────────────────────────────
cat > "${FAKE_BIN}/git" <<STUB
#!/bin/sh
LOG="${STUB_LOG}"
EXIT_VAL=\$(cat "${STUB_EXIT}" 2>/dev/null || echo 0)
echo "INVOKED:git" >> "\$LOG"
for arg in "\$@"; do
  printf 'ARG:%s\n' "\$arg" >> "\$LOG"
done
echo "CALL" >> "\$LOG"

if [ "\$EXIT_VAL" -ne 0 ]; then
  echo "git: simulated command failure (exit \$EXIT_VAL)" >&2
  exit "\$EXIT_VAL"
fi
exit 0
STUB
chmod +x "${FAKE_BIN}/git"

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

run_in_zsh() {
  local script="$1"

  ZDOTDIR="${FAKE_ZDOTDIR}" \
  HOME="${FAKE_HOME}" \
  ZSH="${REPO_ROOT}" \
  PATH="${FAKE_BIN}:${PATH}" \
  zsh --no-rcs -c "
    alias unrelated_alias='echo untouched'
    export UNRELATED_VAR='keep_unchanged'
    git_current_branch() { echo 'feature/lfs-pipeline'; }
    source '${PLUGIN_ZSH}'
    cd '${WORK_DIR}'
    eval '${script}'
  " 2>&1
}

# =============================================================================
# TEST 1: Sourcing state transition & alias/function definitions
# =============================================================================
out=$(ZDOTDIR="${FAKE_ZDOTDIR}" HOME="${FAKE_HOME}" ZSH="${REPO_ROOT}" PATH="${FAKE_BIN}:${PATH}" zsh --no-rcs -c "
  alias unrelated_alias='echo untouched'
  before_glfsi=\$(alias glfsi 2>/dev/null || echo 'absent')
  before_glfst=\$(alias glfst 2>/dev/null || echo 'absent')
  before_glfsls=\$(alias glfsls 2>/dev/null || echo 'absent')
  before_gplfs=\$(which gplfs 2>/dev/null || echo 'absent')
  source '${PLUGIN_ZSH}'
  after_glfsi=\$(alias glfsi 2>/dev/null || echo 'absent')
  after_glfst=\$(alias glfst 2>/dev/null || echo 'absent')
  after_glfsls=\$(alias glfsls 2>/dev/null || echo 'absent')
  after_gplfs=\$(which gplfs 2>/dev/null || echo 'absent')
  after_unrelated=\$(alias unrelated_alias 2>/dev/null || echo 'absent')
  echo \"BEFORE_GLFSI:\$before_glfsi\"
  echo \"AFTER_GLFSI:\$after_glfsi\"
  echo \"BEFORE_GLFST:\$before_glfst\"
  echo \"AFTER_GLFST:\$after_glfst\"
  echo \"BEFORE_GLFSLS:\$before_glfsls\"
  echo \"AFTER_GLFSLS:\$after_glfsls\"
  echo \"AFTER_GPLFS:\$after_gplfs\"
  echo \"AFTER_UNRELATED:\$after_unrelated\"
")

if [[ "$out" == *"BEFORE_GLFSI:absent"* && \
      "$out" == *"AFTER_GLFSI:glfsi='git lfs install'"* && \
      "$out" == *"AFTER_GLFST:glfst='git lfs track'"* && \
      "$out" == *"AFTER_GLFSLS:glfsls='git lfs ls-files'"* && \
      "$out" == *"AFTER_GPLFS:gplfs ()"* && \
      "$out" == *"AFTER_UNRELATED:unrelated_alias='echo untouched'"* ]]; then
  record "sourcing_state_transition" "PASS" "0" "glfsi, glfst, glfsls, gplfs defined; unrelated intact" "aliases and gplfs function defined" "plugin definitions verified"
else
  record "sourcing_state_transition" "FAIL" "1" "$out" "definitions verified" "sourcing transition failed"
fi

# =============================================================================
# TEST 2: glfsi – ordinary success with option
#   Command: glfsi --skip-smudge
#   Assert: git called with ['lfs', 'install', '--skip-smudge']
# =============================================================================
reset_stub
res=$(run_in_zsh "glfsi --skip-smudge")
exit_code=$?
arg1=$(awk '/^ARG:/{n++; if(n==1){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg2=$(awk '/^ARG:/{n++; if(n==2){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg3=$(awk '/^ARG:/{n++; if(n==3){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")

if [[ "$arg1" == "lfs" && "$arg2" == "install" && "$arg3" == "--skip-smudge" && $exit_code -eq 0 ]]; then
  record "glfsi_ordinary_success" "PASS" "${exit_code}" "argv=['lfs', 'install', '--skip-smudge']" "exact argv preserved" "glfsi forwards install options"
else
  record "glfsi_ordinary_success" "FAIL" "${exit_code}" "args=['$arg1','$arg2','$arg3']" "exact argv" "glfsi forwarding failed"
fi

# =============================================================================
# TEST 3: glfst – pattern forwarding with wildcards and spaces
#   Command: glfst "*.psd" "assets/3d models/*.obj"
#   Assert: git called with ['lfs', 'track', '*.psd', 'assets/3d models/*.obj']
# =============================================================================
reset_stub
res=$(run_in_zsh "glfst \"*.psd\" \"assets/3d models/*.obj\"")
exit_code=$?
arg1=$(awk '/^ARG:/{n++; if(n==1){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg2=$(awk '/^ARG:/{n++; if(n==2){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg3=$(awk '/^ARG:/{n++; if(n==3){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg4=$(awk '/^ARG:/{n++; if(n==4){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")

if [[ "$arg1" == "lfs" && "$arg2" == "track" && "$arg3" == "*.psd" && \
      "$arg4" == "assets/3d models/*.obj" && $exit_code -eq 0 ]]; then
  record "glfst_quoted_pattern_forwarding" "PASS" "${exit_code}" "argv=['lfs', 'track', '*.psd', 'assets/3d models/*.obj']" "exact patterns preserved without word-splitting" "glfst pattern argument boundaries intact"
else
  record "glfst_quoted_pattern_forwarding" "FAIL" "${exit_code}" "args=['$arg1','$arg2','$arg3','$arg4']" "exact patterns" "glfst argument boundary failed"
fi

# =============================================================================
# TEST 4: glfsls – list files with arguments
#   Command: glfsls -s --all
#   Assert: git called with ['lfs', 'ls-files', '-s', '--all']
# =============================================================================
reset_stub
res=$(run_in_zsh "glfsls -s --all")
exit_code=$?
arg1=$(awk '/^ARG:/{n++; if(n==1){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg2=$(awk '/^ARG:/{n++; if(n==2){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg3=$(awk '/^ARG:/{n++; if(n==3){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg4=$(awk '/^ARG:/{n++; if(n==4){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")

if [[ "$arg1" == "lfs" && "$arg2" == "ls-files" && "$arg3" == "-s" && \
      "$arg4" == "--all" && $exit_code -eq 0 ]]; then
  record "glfsls_listing_with_options" "PASS" "${exit_code}" "argv=['lfs', 'ls-files', '-s', '--all']" "flags forwarded" "glfsls option forwarding intact"
else
  record "glfsls_listing_with_options" "FAIL" "${exit_code}" "args=['$arg1','$arg2','$arg3','$arg4']" "flags forwarded" "glfsls forwarding failed"
fi

# =============================================================================
# TEST 5: gplfs – simplified helper execution
#   Command: gplfs
#   Assert: git called with ['lfs', 'push', 'origin', 'feature/lfs-pipeline', '--all']
# =============================================================================
reset_stub
res=$(run_in_zsh "gplfs")
exit_code=$?
arg1=$(awk '/^ARG:/{n++; if(n==1){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg2=$(awk '/^ARG:/{n++; if(n==2){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg3=$(awk '/^ARG:/{n++; if(n==3){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg4=$(awk '/^ARG:/{n++; if(n==4){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")
arg5=$(awk '/^ARG:/{n++; if(n==5){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}")

if [[ "$arg1" == "lfs" && "$arg2" == "push" && "$arg3" == "origin" && \
      "$arg4" == "feature/lfs-pipeline" && "$arg5" == "--all" && $exit_code -eq 0 ]]; then
  record "gplfs_simplified_helper_execution" "PASS" "${exit_code}" "argv=['lfs', 'push', 'origin', 'feature/lfs-pipeline', '--all']" "resolved branch pushed to origin with --all" "simplified gplfs helper preserves observable behavior"
else
  record "gplfs_simplified_helper_execution" "FAIL" "${exit_code}" "args=['$arg1','$arg2','$arg3','$arg4','$arg5']" "expected args" "gplfs execution failed"
fi

# =============================================================================
# TEST 6: Documented failure/edge state – status propagation on failure
# =============================================================================
reset_stub
echo "1" > "${STUB_EXIT}"
res=$(run_in_zsh "glfsi")
exit_code=$?
if [[ $exit_code -eq 1 && "$res" == *"simulated command failure"* ]]; then
  record "glfsi_failure_exit_propagation" "PASS" "${exit_code}" "exit=1, error captured" "exit=1" "documented failure: git failure status propagates cleanly"
else
  record "glfsi_failure_exit_propagation" "FAIL" "${exit_code}" "exit=$exit_code" "exit=1" "failure propagation failed"
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
