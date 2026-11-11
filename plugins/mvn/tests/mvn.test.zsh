#!/usr/bin/env zsh
# Fixture test for the mvn plugin. Runs in a private sandbox and never calls real mvn or mvnw.
# Usage: zsh -f plugins/mvn/tests/mvn.test.zsh [path/to/mvn.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/mvn.plugin.zsh}
test_dir=$(mktemp -d "${${TMPDIR:-/tmp}%/}/mvn-test.XXXXXX") || exit 1
test_dir=${test_dir:A}
orig_path=($path)
orig_pwd=$PWD
trap 'cd "$orig_pwd" 2>/dev/null || true; path=($orig_path); command rm -rf -- "$test_dir"' EXIT

export HOME=$test_dir/home ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export MVN_LOG=$test_dir/mvn.log MVNW_LOG=$test_dir/mvnw.log STUB_STATUS_FILE=$test_dir/stub_status

proj_root=$test_dir/proj
proj_sub=$proj_root/sub/deep
noexec_root=$test_dir/noexec_proj
noexec_sub=$noexec_root/sub
plain_sub=$test_dir/plain/nested

command mkdir -p -- "$HOME" "$ZDOTDIR" "$ZSH_CACHE_DIR" "$test_dir/bin" "$test_dir/empty_bin" "$proj_sub" "$noexec_sub" "$plain_sub"

# Stub mvn: logs invoked target, argc, and each argument.
command cat >| "$test_dir/bin/mvn" <<'STUB'
#!/bin/sh
{ echo "target=mvn"; echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$MVN_LOG"
status=0
if [ -r "$STUB_STATUS_FILE" ]; then
  read -r status < "$STUB_STATUS_FILE"
fi
exit "$status"
STUB
command chmod 0755 "$test_dir/bin/mvn" || exit 1

# Executable wrapper stub at proj/mvnw
command cat >| "$proj_root/mvnw" <<'STUB'
#!/bin/sh
{ echo "target=mvnw"; echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$MVNW_LOG"
status=0
if [ -r "$STUB_STATUS_FILE" ]; then
  read -r status < "$STUB_STATUS_FILE"
fi
exit "$status"
STUB
command chmod 0755 "$proj_root/mvnw" || exit 1

# Non-executable wrapper decoy at noexec_proj/mvnw (0644)
command cat >| "$noexec_root/mvnw" <<'STUB'
#!/bin/sh
echo "target=nonexec_mvnw" >> "$MVNW_LOG"
exit 99
STUB
command chmod 0644 "$noexec_root/mvnw" || exit 1

path=($test_dir/bin)
source "$plugin" || exit 1

typeset -i tests=0 failures=0

check_mvn() {
  # check_mvn <success|edge> <description> <workdir> <use_bin:1|0> <stub_exit> <expected_status> <expected_stdout> <expected_stderr> <expected_mvn_log> <expected_mvnw_log> <command>
  local kind=$1 description=$2 workdir=$3 use_bin=$4 stub_exit=$5
  local expected_status=$6 expected_stdout=$7 expected_stderr=$8
  local expected_mvn_log=$9 expected_mvnw_log=${10} cmd=${11}
  local actual_status actual_stdout actual_stderr actual_mvn_log actual_mvnw_log
  local pwd_before pwd_after dir_leaked output_ok status_ok state_ok

  cd "$workdir" || exit 1
  pwd_before=${PWD:A}
  : >| "$MVN_LOG"
  : >| "$MVNW_LOG"
  print -r -- "$stub_exit" >| "$STUB_STATUS_FILE"
  if [[ $use_bin == 1 ]]; then
    path=($test_dir/bin)
  else
    path=($test_dir/empty_bin)
  fi

  eval "$cmd" >| "$test_dir/stdout" 2>| "$test_dir/stderr"
  actual_status=$?
  actual_stdout=$(<"$test_dir/stdout")
  actual_stderr=$(<"$test_dir/stderr")
  actual_mvn_log=$(<"$MVN_LOG")
  actual_mvnw_log=$(<"$MVNW_LOG")
  pwd_after=${PWD:A}
  dir_leaked=${+dir}

  # Assert output, exit status, and repository/shell state separately.
  output_ok=0
  if [[ $actual_stdout == "$expected_stdout" ]]; then
    if [[ $use_bin == 1 && $actual_stderr == "$expected_stderr" ]]; then
      output_ok=1
    elif [[ $use_bin == 0 && $actual_stderr == *"$expected_stderr"* ]]; then
      output_ok=1
    fi
  fi
  status_ok=0
  [[ $actual_status == $expected_status ]] && status_ok=1
  state_ok=0
  if [[ $actual_mvn_log == "$expected_mvn_log" \
     && $actual_mvnw_log == "$expected_mvnw_log" \
     && $pwd_after == "$pwd_before" \
     && $dir_leaked == 0 ]]; then
    state_ok=1
  fi

  (( tests++ ))
  if (( output_ok && status_ok && state_ok )); then
    print -r -- "PASS: [$kind] $description"
  else
    print -r -- "FAIL: [$kind] $description"
    (( failures++ ))
  fi
  print -r -- "  status: $actual_status (expected $expected_status, ok=$status_ok)"
  print -r -- "  output: stdout=${(qqq)actual_stdout} stderr=${(qqq)${actual_stderr//$test_dir/<sandbox>}} (ok=$output_ok)"
  print -r -- "  mvn:    ${(j: | :)${(f)actual_mvn_log}}"
  print -r -- "  mvnw:   ${(j: | :)${(f)actual_mvnw_log}}"
  print -r -- "  state:  pwd_unchanged=$([[ $pwd_after == "$pwd_before" ]] && echo yes || echo no) dir_leaked=$dir_leaked (ok=$state_ok)"
}

check_mvn success \
  'mvnboot -Dx="a b" from subfolder invokes executable root mvnw with 2 args and stderr notice' \
  "$proj_sub" 1 0 0 \
  '' "Running \`${proj_root}/mvnw\`..." \
  '' $'target=mvnw\nargc=2\narg=spring-boot:run\narg=-Dx=a b' \
  'mvnboot -Dx="a b"'

check_mvn success \
  'mvnag without mvnw falls back to mvn stub with archetype:generate and empty stderr' \
  "$plain_sub" 1 0 0 \
  '' '' \
  $'target=mvn\nargc=1\narg=archetype:generate' '' \
  'mvnag'

check_mvn success \
  'wrapper exit status 3 passes through mvnboot unchanged' \
  "$proj_sub" 1 3 3 \
  '' "Running \`${proj_root}/mvnw\`..." \
  '' $'target=mvnw\nargc=1\narg=spring-boot:run' \
  'mvnboot'

check_mvn edge \
  'non-executable mvnw is skipped and falls back to mvn stub' \
  "$noexec_sub" 1 0 0 \
  '' '' \
  $'target=mvn\nargc=1\narg=-q' '' \
  'mvn -q'

check_mvn edge \
  'bare mvn with no arguments forwards argc=0 to mvn stub' \
  "$plain_sub" 1 0 0 \
  '' '' \
  $'target=mvn\nargc=0' '' \
  'mvn'

check_mvn edge \
  'missing mvn on PATH without mvnw exits 127 and preserves shell state' \
  "$plain_sub" 0 0 127 \
  '' 'command not found: mvn' \
  '' '' \
  'mvn'

cd "$orig_pwd" || exit 1
print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
