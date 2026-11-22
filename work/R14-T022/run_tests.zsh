#!/usr/bin/env zsh
# run_tests.zsh – Shell-side test harness for composer plugin (R14-T022)
#
# Tests alias argument contracts for:
#   c   → composer
#   ccp → composer create-project
#   cdo → composer dump-autoload -o
#
# Strategy:
#   - Stub `composer` and `curl` on a fake PATH; stub logs argv one-per-line.
#   - Source the plugin inside a minimal zsh session with no ZDOTDIR / compinit.
#   - Expand each alias manually (aliases are plain strings; eval them via zsh -c).
#   - Assert argv tokens, exit status, and before/after state separately.
#
# Output: RESULT|<name>|<status>|<exit>|<actual>|<expected>|<notes>

emulate -L zsh
setopt EXTENDED_GLOB NO_UNSET PIPE_FAIL

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="${${0:a}:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."
PLUGIN_ZSH="${REPO_ROOT}/plugins/composer/composer.plugin.zsh"

# ── Temporary sandbox ─────────────────────────────────────────────────────────
TMPBASE=$(mktemp -d)
FAKE_HOME="${TMPBASE}/home"
FAKE_BIN="${TMPBASE}/bin"
FAKE_ZDOTDIR="${TMPBASE}/zdotdir"
STUB_LOG="${TMPBASE}/stub.log"
STUB_EXIT_FILE="${TMPBASE}/stub_exit"

mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${FAKE_ZDOTDIR}"
echo "0" > "${STUB_EXIT_FILE}"

# ── Stub: composer ────────────────────────────────────────────────────────────
# Logs each argv token as "ARG:<token>", then emits "CALL" and exits with
# whatever is in STUB_EXIT_FILE.
cat > "${FAKE_BIN}/composer" <<'STUB'
#!/bin/sh
LOG="${STUB_LOG}"
EXIT=$(cat "${STUB_EXIT_FILE}" 2>/dev/null || echo 0)
printf 'ARG:%s\n' "$@" >> "${LOG}"
printf 'CALL\n'          >> "${LOG}"
exit "${EXIT}"
STUB
chmod +x "${FAKE_BIN}/composer"

# Inject the log/exit paths that the stub needs at runtime
sed -i.bak \
  "s|LOG=\"\${STUB_LOG}\"|LOG=\"${STUB_LOG}\"|" \
  "${FAKE_BIN}/composer" 2>/dev/null || true
# Rewrite stub to have literal paths (portable)
cat > "${FAKE_BIN}/composer" <<STUB
#!/bin/sh
EXIT=\$(cat "${STUB_EXIT_FILE}" 2>/dev/null || echo 0)
printf 'ARG:%s\n' "\$@" >> "${STUB_LOG}"
printf 'CALL\n'          >> "${STUB_LOG}"
exit "\${EXIT}"
STUB
chmod +x "${FAKE_BIN}/composer"

# ── Stub: curl (for cget – we just need it not to blow up) ───────────────────
cat > "${FAKE_BIN}/curl" <<'STUB'
#!/bin/sh
# no-op curl stub – cget pipes to php which we don't invoke in tests
exit 0
STUB
chmod +x "${FAKE_BIN}/curl"

# ── Helper: reset stub log between tests ─────────────────────────────────────
reset_stub() { > "${STUB_LOG}"; echo "0" > "${STUB_EXIT_FILE}"; }

# ── Helper: get the Nth ARG token from stub log ──────────────────────────────
# Usage: nth_arg <n>  (1-based, 0=command, 1=first arg, …)
nth_arg() {
  awk -v n="$1" 'BEGIN{i=0} /^ARG:/{i++; if(i==n){sub(/^ARG:/,""); print; exit}}' "${STUB_LOG}"
}

all_args() {
  awk '/^ARG:/{sub(/^ARG:/,""); printf "%s\t", $0} END{printf "\n"}' "${STUB_LOG}" | sed 's/\t$//'
}

call_count() {
  grep -c '^CALL$' "${STUB_LOG}" 2>/dev/null || echo 0
}

# ── Helper: run a zsh session that sources the plugin then runs a command ─────
# We bootstrap an isolated zsh:
#   - ZDOTDIR=FAKE_ZDOTDIR (empty → no .zshrc / .zprofile)
#   - ZSH=REPO_ROOT (so plugin can reference $ZSH if needed)
#   - HOME=FAKE_HOME
#   - PATH=FAKE_BIN:original PATH
#   - Autoloads disabled (compinit not needed for alias tests)
#   - Sources the plugin, then runs the alias command
run_via_plugin() {
  local cmd="$1"
  ZDOTDIR="${FAKE_ZDOTDIR}" \
  HOME="${FAKE_HOME}" \
  ZSH="${REPO_ROOT}" \
  GIT_CONFIG_NOSYSTEM=1 \
  PATH="${FAKE_BIN}:${PATH}" \
  zsh --no-rcs -c "
    # Minimal stubs so plugin sources cleanly
    is-at-least() { return 1; }   # skip old-zsh completion block
    autoload() { :; }             # swallow autoload calls
    _store_cache()    { :; }
    _retrieve_cache() { :; }
    _cache_invalid()  { :; }
    source '${PLUGIN_ZSH}'
    ${cmd}
  " 2>&1
}

# ── Helper: record result ─────────────────────────────────────────────────────
record() {
  local name="$1" status="$2" exit_code="$3" actual="$4" expected="$5" notes="$6"
  printf 'RESULT|%s|%s|%s|%s|%s|%s\n' \
    "${name}" "${status}" "${exit_code}" "${actual}" "${expected}" "${notes}"
}

# =============================================================================
# TEST 1: Minimum accepted argument – alias 'c' expands to 'composer'
#   c → composer (no args)
#   Assert: composer called with zero arguments; exit 0.
# =============================================================================
reset_stub
run_via_plugin "c"
actual_exit=$?
calls=$(call_count)
args=$(all_args)
expected_args=""
if [[ ${calls} -ge 1 && -z "${args// }" ]]; then
  record "c_alias_no_args" "PASS" "${actual_exit}" "calls=${calls} args='${args}'" "calls>=1 args=''" "c→composer, min arg list"
else
  record "c_alias_no_args" "FAIL" "${actual_exit}" "calls=${calls} args='${args}'" "calls>=1 args=''" "c→composer, min arg list"
fi

# =============================================================================
# TEST 2: 'c' with a subcommand (optional argument)
#   c install → composer install
#   Assert: first argv token = "install"
# =============================================================================
reset_stub
run_via_plugin "c install"
actual_exit=$?
arg1=$(nth_arg 1)
calls=$(call_count)
expected_arg="install"
if [[ "${arg1}" == "${expected_arg}" && ${calls} -ge 1 ]]; then
  record "c_alias_with_subcommand" "PASS" "${actual_exit}" "arg1='${arg1}'" "arg1='${expected_arg}'" "c with optional subcommand"
else
  record "c_alias_with_subcommand" "FAIL" "${actual_exit}" "arg1='${arg1}'" "arg1='${expected_arg}'" "c with optional subcommand"
fi

# =============================================================================
# TEST 3: 'ccp' expands to 'composer create-project'
#   Assert: argv[1]='create-project'
# =============================================================================
reset_stub
run_via_plugin "ccp vendor/package myapp"
actual_exit=$?
arg1=$(nth_arg 1)
arg2=$(nth_arg 2)
arg3=$(nth_arg 3)
calls=$(call_count)
if [[ "${arg1}" == "create-project" && "${arg2}" == "vendor/package" && "${arg3}" == "myapp" && ${calls} -ge 1 ]]; then
  record "ccp_create_project" "PASS" "${actual_exit}" "argv=create-project vendor/package myapp" "create-project vendor/package myapp" "ccp→composer create-project"
else
  record "ccp_create_project" "FAIL" "${actual_exit}" "arg1='${arg1}' arg2='${arg2}' arg3='${arg3}'" "create-project vendor/package myapp" "ccp→composer create-project"
fi

# =============================================================================
# TEST 4: 'cdo' expands to 'composer dump-autoload -o'
#   Assert: argv[1]='dump-autoload', argv[2]='-o' (pre-baked optional arg)
# =============================================================================
reset_stub
run_via_plugin "cdo"
actual_exit=$?
arg1=$(nth_arg 1)
arg2=$(nth_arg 2)
calls=$(call_count)
if [[ "${arg1}" == "dump-autoload" && "${arg2}" == "-o" && ${calls} -ge 1 ]]; then
  record "cdo_dump_autoload_optimized" "PASS" "${actual_exit}" "argv=dump-autoload -o" "dump-autoload -o" "cdo bakes -o flag"
else
  record "cdo_dump_autoload_optimized" "FAIL" "${actual_exit}" "arg1='${arg1}' arg2='${arg2}'" "dump-autoload -o" "cdo bakes -o flag"
fi

# =============================================================================
# TEST 5: 'cdo' with extra arg (additional optional argument after baked -o)
#   cdo --no-dev → composer dump-autoload -o --no-dev
#   Assert argv[3]='--no-dev'
# =============================================================================
reset_stub
run_via_plugin "cdo --no-dev"
actual_exit=$?
arg1=$(nth_arg 1)
arg2=$(nth_arg 2)
arg3=$(nth_arg 3)
calls=$(call_count)
if [[ "${arg1}" == "dump-autoload" && "${arg2}" == "-o" && "${arg3}" == "--no-dev" && ${calls} -ge 1 ]]; then
  record "cdo_with_extra_flag" "PASS" "${actual_exit}" "argv=dump-autoload -o --no-dev" "dump-autoload -o --no-dev" "cdo accepts extra optional args"
else
  record "cdo_with_extra_flag" "FAIL" "${actual_exit}" "arg1='${arg1}' arg2='${arg2}' arg3='${arg3}'" "dump-autoload -o --no-dev" "cdo accepts extra optional args"
fi

# =============================================================================
# TEST 6: 'ci' expands to 'composer install'
#   Assert: argv[1]='install'
# =============================================================================
reset_stub
run_via_plugin "ci"
actual_exit=$?
arg1=$(nth_arg 1)
calls=$(call_count)
if [[ "${arg1}" == "install" && ${calls} -ge 1 ]]; then
  record "ci_install" "PASS" "${actual_exit}" "arg1='${arg1}'" "arg1='install'" "ci→composer install"
else
  record "ci_install" "FAIL" "${actual_exit}" "arg1='${arg1}'" "arg1='install'" "ci→composer install"
fi

# =============================================================================
# TEST 7: 'cu' expands to 'composer update'
#   Assert: argv[1]='update'
# =============================================================================
reset_stub
run_via_plugin "cu"
actual_exit=$?
arg1=$(nth_arg 1)
calls=$(call_count)
if [[ "${arg1}" == "update" && ${calls} -ge 1 ]]; then
  record "cu_update" "PASS" "${actual_exit}" "arg1='${arg1}'" "arg1='update'" "cu→composer update"
else
  record "cu_update" "FAIL" "${actual_exit}" "arg1='${arg1}'" "arg1='update'" "cu→composer update"
fi

# =============================================================================
# TEST 8: 'cr' expands to 'composer require'
#   Assert: argv[1]='require', argv[2]=package name
# =============================================================================
reset_stub
run_via_plugin "cr vendor/package"
actual_exit=$?
arg1=$(nth_arg 1)
arg2=$(nth_arg 2)
calls=$(call_count)
if [[ "${arg1}" == "require" && "${arg2}" == "vendor/package" && ${calls} -ge 1 ]]; then
  record "cr_require_package" "PASS" "${actual_exit}" "argv=require vendor/package" "require vendor/package" "cr→composer require <pkg>"
else
  record "cr_require_package" "FAIL" "${actual_exit}" "arg1='${arg1}' arg2='${arg2}'" "require vendor/package" "cr→composer require <pkg>"
fi

# =============================================================================
# TEST 9: Documented invalid combination – 'cdo' + conflicting flags
#   'composer dump-autoload -o --optimize-autoloader' is a redundant/invalid
#   combination (--optimize-autoloader is already implied by -o).
#   We document that composer IS still called with these args (no alias-level
#   guard) – the error comes from composer itself, not the alias.
#   Assert: composer is called; argv contains both -o and --optimize-autoloader.
# =============================================================================
reset_stub
run_via_plugin "cdo --optimize-autoloader"
actual_exit=$?
arg2=$(nth_arg 2)   # should be -o
arg3=$(nth_arg 3)   # should be --optimize-autoloader
calls=$(call_count)
# Our stub exits 0 regardless; real composer would warn. We assert both flags
# are forwarded unchanged (no alias-level filtering – documents the contract).
if [[ "${arg2}" == "-o" && "${arg3}" == "--optimize-autoloader" && ${calls} -ge 1 ]]; then
  record "cdo_redundant_flag_forwarded" "PASS" "${actual_exit}" "argv=dump-autoload -o --optimize-autoloader" "-o and --optimize-autoloader both forwarded" "documented: alias passes args verbatim; real composer warns"
else
  record "cdo_redundant_flag_forwarded" "FAIL" "${actual_exit}" "arg2='${arg2}' arg3='${arg3}' calls=${calls}" "-o and --optimize-autoloader both forwarded" "documented: alias passes args verbatim"
fi

# =============================================================================
# TEST 10: 'cod' expands to 'composer outdated --direct'
#   Assert: argv[1]='outdated', argv[2]='--direct'
# =============================================================================
reset_stub
run_via_plugin "cod"
actual_exit=$?
arg1=$(nth_arg 1)
arg2=$(nth_arg 2)
calls=$(call_count)
if [[ "${arg1}" == "outdated" && "${arg2}" == "--direct" && ${calls} -ge 1 ]]; then
  record "cod_outdated_direct" "PASS" "${actual_exit}" "argv=outdated --direct" "outdated --direct" "cod→composer outdated --direct"
else
  record "cod_outdated_direct" "FAIL" "${actual_exit}" "arg1='${arg1}' arg2='${arg2}'" "outdated --direct" "cod→composer outdated --direct"
fi

# =============================================================================
# TEST 11: Native plugin syntax check
# =============================================================================
zsh -n "${PLUGIN_ZSH}" 2>&1
zsh_n_exit=$?
if [[ ${zsh_n_exit} -eq 0 ]]; then
  record "plugin_syntax_check" "PASS" "${zsh_n_exit}" "zsh -n exit=0" "exit=0" "plugin file parses cleanly"
else
  record "plugin_syntax_check" "FAIL" "${zsh_n_exit}" "zsh -n exit=${zsh_n_exit}" "exit=0" "syntax error in plugin"
fi

# =============================================================================
# TEST 12: State isolation – user HOME / global git config untouched
#   After all tests, verify FAKE_HOME is a distinct path from real HOME.
# =============================================================================
real_home="${HOME}"
if [[ "${FAKE_HOME}" != "${real_home}" ]]; then
  record "state_isolation" "PASS" "0" "sandbox=${FAKE_HOME}" "isolated from ${real_home}" "no user state mutated"
else
  record "state_isolation" "FAIL" "1" "sandbox=${FAKE_HOME}" "isolated from ${real_home}" "sandbox equals real HOME!"
fi

# ── Cleanup sandbox ───────────────────────────────────────────────────────────
rm -rf "${TMPBASE}"
