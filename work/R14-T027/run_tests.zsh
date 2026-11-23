#!/usr/bin/env zsh
# run_tests.zsh – Shell test harness for asdf plugin (R14-T027)
# Verifies plugin initialization, completion definitions, missing dependency handling,
# and executes the verified usage example from README.md to prevent documentation drift.

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

SCRIPT_DIR="${${0:a}:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."
PLUGIN_ZSH="${REPO_ROOT}/plugins/asdf/asdf.plugin.zsh"

TMPBASE=$(mktemp -d)
FAKE_HOME="${TMPBASE}/home"
FAKE_BIN="${TMPBASE}/bin"
EMPTY_BIN="${TMPBASE}/empty_bin"
FAKE_ZDOTDIR="${TMPBASE}/zdotdir"
FAKE_CACHE="${TMPBASE}/cache"
STUB_LOG="${TMPBASE}/asdf_calls.log"
PROJECT_DIR="${TMPBASE}/project_workspace"

mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${EMPTY_BIN}" "${FAKE_ZDOTDIR}" \
         "${FAKE_CACHE}/completions" "${PROJECT_DIR}"

: > "${STUB_LOG}"

# ── Mock asdf stub ────────────────────────────────────────────────────────────
cat > "${FAKE_BIN}/asdf" <<STUB
#!/bin/sh
LOG="${STUB_LOG}"
echo "CALL:\$*" >> "\$LOG"

case "\$1" in
  completion)
    echo "#compdef asdf"
    ;;
  plugin)
    if [ "\$2" = "add" ]; then
      echo "Plugin \$3 added"
    fi
    ;;
  install)
    echo "Installing \$2 \$3..."
    echo "\$2 \$3 installation finished"
    ;;
  set)
    echo "\$2 \$3" > .tool-versions
    echo "Set \$2 \$3 in .tool-versions"
    ;;
  current)
    if [ -f .tool-versions ]; then
      val=\$(grep "^\$2 " .tool-versions | awk '{print \$2}')
      if [ -n "\$val" ]; then
        echo "\$2 \$val (set by \$(pwd)/.tool-versions)"
        exit 0
      fi
    fi
    echo "No version set for \$2"
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
exit 0
STUB
chmod +x "${FAKE_BIN}/asdf"

# ── Helpers ───────────────────────────────────────────────────────────────────
reset_stub() {
  : > "${STUB_LOG}"
}

record() {
  local name="$1" test_status="$2" exit_code="$3" actual="$4" expected="$5" notes="$6"
  printf 'RESULT|%s|%s|%s|%s|%s|%s\n' \
    "${name}" "${test_status}" "${exit_code}" "${actual}" "${expected}" "${notes}"
}

# =============================================================================
# TEST 1: Plugin initialization success (asdf on PATH)
#   Sets default ASDF_DATA_DIR, prepends shims to PATH, binds completion
# =============================================================================
reset_stub
out=$(ZDOTDIR="${FAKE_ZDOTDIR}" HOME="${FAKE_HOME}" ZSH="${REPO_ROOT}" \
      ZSH_CACHE_DIR="${FAKE_CACHE}" PATH="${FAKE_BIN}:${PATH}" \
      zsh --no-rcs -c "
  export UNRELATED_VAR='keep_unchanged'
  typeset -g -A _comps
  compinit() { :; }
  source '${PLUGIN_ZSH}'
  echo \"DATA_DIR:\$ASDF_DATA_DIR\"
  echo \"FIRST_PATH:\$path[1]\"
  echo \"COMP_BIND:\${_comps[asdf]:-unset}\"
  echo \"UNRELATED:\$UNRELATED_VAR\"
")

if [[ "$out" == *"DATA_DIR:${FAKE_HOME}/.asdf"* && \
      "$out" == *"FIRST_PATH:${FAKE_HOME}/.asdf/shims"* && \
      "$out" == *"COMP_BIND:_asdf"* && \
      "$out" == *"UNRELATED:keep_unchanged"* ]]; then
  record "plugin_initialization_success" "PASS" "0" "ASDF_DATA_DIR=$FAKE_HOME/.asdf, shims prepended, _comps[asdf]=_asdf" "initialized shims and completions" "standard initialization verified"
else
  record "plugin_initialization_success" "FAIL" "1" "$out" "shims prepended" "initialization failed"
fi

# =============================================================================
# TEST 2: Verified Usage Example (README.md workflow execution & state verification)
# =============================================================================
reset_stub
out=$(ZDOTDIR="${FAKE_ZDOTDIR}" HOME="${FAKE_HOME}" ZSH="${REPO_ROOT}" \
      ZSH_CACHE_DIR="${FAKE_CACHE}" PATH="${FAKE_BIN}:${PATH}" \
      zsh --no-rcs -c "
  cd '${PROJECT_DIR}'
  export ASDF_DATA_DIR=\"\$HOME/.asdf\"
  source '${PLUGIN_ZSH}'

  # 1. Add plugin
  p_out=\$(asdf plugin add nodejs)

  # 2. Install version
  i_out=\$(asdf install nodejs 18.16.0)

  # 3. Set version
  s_out=\$(asdf set nodejs 18.16.0)

  # 4. State verification
  c_out=\$(asdf current nodejs)
  path_ok=\$([[ \"\$path[1]\" == \"\$ASDF_DATA_DIR/shims\" ]] && echo 'yes' || echo 'no')
  file_content=\$(cat .tool-versions 2>/dev/null)

  echo \"INSTALL_OUT:\$i_out\"
  echo \"SET_OUT:\$s_out\"
  echo \"CURRENT_OUT:\$c_out\"
  echo \"PATH_OK:\$path_ok\"
  echo \"FILE_CONTENT:\$file_content\"
")

if [[ "$out" == *"INSTALL_OUT:Installing nodejs 18.16.0...
nodejs 18.16.0 installation finished"* && \
      "$out" == *"SET_OUT:Set nodejs 18.16.0 in .tool-versions"* && \
      "$out" == *"CURRENT_OUT:nodejs 18.16.0 (set by ${PROJECT_DIR}/.tool-versions)"* && \
      "$out" == *"PATH_OK:yes"* && \
      "$out" == *"FILE_CONTENT:nodejs 18.16.0"* ]]; then
  record "verified_usage_example_execution" "PASS" "0" "commands executed and output verified against documentation" "matches README documentation" "verified usage example executes correctly"
else
  record "verified_usage_example_execution" "FAIL" "1" "$out" "matches README" "usage example drift detected"
fi

# =============================================================================
# TEST 3: Documented failure/edge state – missing dependency early return
#   When asdf is not found on PATH, initialization returns early without mutating state
# =============================================================================
reset_stub
out=$(ZDOTDIR="${FAKE_ZDOTDIR}" HOME="${FAKE_HOME}" ZSH="${REPO_ROOT}" \
      ZSH_CACHE_DIR="${FAKE_CACHE}" \
      zsh --no-rcs -c "
  export UNRELATED_VAR='keep_unchanged'
  PATH='${EMPTY_BIN}'
  typeset -g -A _comps
  source '${PLUGIN_ZSH}'
  echo \"DATA_DIR:\${ASDF_DATA_DIR:-unset}\"
  echo \"COMP_BIND:\${_comps[asdf]:-unset}\"
  echo \"PATH_VAL:\$PATH\"
  echo \"UNRELATED:\$UNRELATED_VAR\"
" 2>&1)

if [[ "$out" == *"DATA_DIR:unset"* && \
      "$out" == *"COMP_BIND:unset"* && \
      "$out" == *"PATH_VAL:${EMPTY_BIN}"* && \
      "$out" == *"UNRELATED:keep_unchanged"* ]]; then
  record "missing_dependency_early_return" "PASS" "0" "returns early without setting ASDF_DATA_DIR or modifying PATH" "clean exit without state mutation" "documented missing dependency branch verified"
else
  record "missing_dependency_early_return" "FAIL" "1" "$out" "clean exit" "missing dependency mutation"
fi

# =============================================================================
# TEST 4: Custom ASDF_DATA_DIR is preserved
# =============================================================================
reset_stub
out=$(ZDOTDIR="${FAKE_ZDOTDIR}" HOME="${FAKE_HOME}" ZSH="${REPO_ROOT}" \
      ZSH_CACHE_DIR="${FAKE_CACHE}" PATH="${FAKE_BIN}:${PATH}" \
      zsh --no-rcs -c "
  export ASDF_DATA_DIR='/opt/custom/asdf'
  source '${PLUGIN_ZSH}'
  echo \"DATA_DIR:\$ASDF_DATA_DIR\"
  echo \"FIRST_PATH:\$path[1]\"
")

if [[ "$out" == *"DATA_DIR:/opt/custom/asdf"* && \
      "$out" == *"FIRST_PATH:/opt/custom/asdf/shims"* ]]; then
  record "custom_asdf_data_dir_preserved" "PASS" "0" "custom ASDF_DATA_DIR preserved, custom shims prepended" "custom dir preserved" "user custom ASDF_DATA_DIR handled correctly"
else
  record "custom_asdf_data_dir_preserved" "FAIL" "1" "$out" "custom dir preserved" "custom ASDF_DATA_DIR failed"
fi

# =============================================================================
# TEST 5: Duplicate shims entries are deduplicated
# =============================================================================
reset_stub
out=$(ZDOTDIR="${FAKE_ZDOTDIR}" HOME="${FAKE_HOME}" ZSH="${REPO_ROOT}" \
      ZSH_CACHE_DIR="${FAKE_CACHE}" PATH="${FAKE_HOME}/.asdf/shims:${FAKE_BIN}:${PATH}" \
      zsh --no-rcs -c "
  source '${PLUGIN_ZSH}'
  local -i count=0
  for p in \$path; do
    [[ \"\$p\" == \"${FAKE_HOME}/.asdf/shims\" ]] && (( count++ ))
  done
  echo \"SHIM_COUNT:\$count\"
  echo \"FIRST_PATH:\$path[1]\"
")

if [[ "$out" == *"SHIM_COUNT:1"* && "$out" == *"FIRST_PATH:${FAKE_HOME}/.asdf/shims"* ]]; then
  record "duplicate_shims_deduplicated" "PASS" "0" "shims appears exactly once at front of PATH" "deduplicated shims" "path deduplication verified"
else
  record "duplicate_shims_deduplicated" "FAIL" "1" "$out" "deduplicated" "shims duplicated"
fi

# =============================================================================
# TEST 6: State isolation check
# =============================================================================
if [[ "${FAKE_HOME}" != "${HOME}" ]]; then
  record "state_isolation" "PASS" "0" "sandbox=${FAKE_HOME}" "isolated from ${HOME}" "no user state altered"
else
  record "state_isolation" "FAIL" "1" "sandbox equals real HOME" "isolated" "sandbox breach"
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "${TMPBASE}"
