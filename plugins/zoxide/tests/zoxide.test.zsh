#!/usr/bin/env zsh
# Characterization fixture test for the zoxide plugin.
# Usage: zsh -f plugins/zoxide/tests/zoxide.test.zsh [path/to/zoxide.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/zoxide.plugin.zsh}
test_dir=$(mktemp -d) || exit 1
orig_path=($path)
trap 'path=($orig_path); command rm -rf -- "$test_dir"' EXIT

export HOME=$test_dir/home ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export STUB_LOG=$test_dir/args.log
command mkdir -p -- "$HOME" "$ZDOTDIR" "$ZSH_CACHE_DIR" "$test_dir/bin" "$test_dir/empty_bin"

command cat >| "$test_dir/bin/zoxide" <<'STUB'
#!/bin/sh
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
printf '%s\n' 'ZOXIDE_FIXTURE=loaded'
STUB
command chmod 0755 "$test_dir/bin/zoxide" || exit 1

typeset -i tests=0 failures=0

run_case() {
  # run_case <success|edge> <description> <use_stub:1|0> <override_mode:unset|value> <override_val> <expected_status> <expected_stdout> <expected_args> <expected_fixture>
  local kind=$1 description=$2 use_stub=$3 override_mode=$4 override_val=$5
  local expected_status=$6 expected_stdout=$7 expected_args=$8 expected_fixture=$9
  local actual_status actual_stdout actual_stderr actual_args fixture_before fixture_after

  unset ZOXIDE_FIXTURE ZOXIDE_CMD_OVERRIDE
  if [[ $override_mode == value ]]; then
    export ZOXIDE_CMD_OVERRIDE=$override_val
  fi
  if [[ $use_stub == 1 ]]; then
    path=($test_dir/bin)
  else
    path=($test_dir/empty_bin)
  fi

  : >| "$STUB_LOG"
  fixture_before=${ZOXIDE_FIXTURE:-__UNSET__}

  source "$plugin" >| "$test_dir/stdout" 2>| "$test_dir/stderr"
  actual_status=$?
  actual_stdout=$(<"$test_dir/stdout")
  actual_stderr=$(<"$test_dir/stderr")
  actual_args=$(<"$STUB_LOG")
  fixture_after=${ZOXIDE_FIXTURE:-__UNSET__}

  (( tests++ ))
  if [[ $actual_status == $expected_status \
     && $actual_stdout == "$expected_stdout" \
     && $actual_stderr == "" \
     && $actual_args == "$expected_args" \
     && $fixture_after == "$expected_fixture" ]]; then
    print -r -- "PASS: [$kind] $description"
  else
    print -r -- "FAIL: [$kind] $description"
    (( failures++ ))
  fi
  print -r -- "  status: $actual_status (expected $expected_status)"
  print -r -- "  stdout: ${(qqq)actual_stdout} (expected ${(qqq)expected_stdout})"
  print -r -- "  stderr: ${(qqq)actual_stderr} (expected \"\")"
  print -r -- "  args:   ${(j: | :)${(f)actual_args}} (expected ${(j: | :)${(f)expected_args}})"
  print -r -- "  state:  fixture_before=$fixture_before fixture_after=$fixture_after (expected $expected_fixture)"
}

run_case success \
  'unset ZOXIDE_CMD_OVERRIDE uses default z and evaluates zoxide init output' \
  1 unset '' 0 '' $'argc=4\narg=init\narg=--cmd\narg=z\narg=zsh' loaded

run_case success \
  'ZOXIDE_CMD_OVERRIDE=j passes j to --cmd' \
  1 value 'j' 0 '' $'argc=4\narg=init\narg=--cmd\narg=j\narg=zsh' loaded

run_case edge \
  'empty ZOXIDE_CMD_OVERRIDE falls back to z' \
  1 value '' 0 '' $'argc=4\narg=init\narg=--cmd\narg=z\narg=zsh' loaded

run_case edge \
  'ZOXIDE_CMD_OVERRIDE with spaces arrives as one argument' \
  1 value 'my cd' 0 '' $'argc=4\narg=init\narg=--cmd\narg=my cd\narg=zsh' loaded

run_case edge \
  'missing zoxide prints install hint, exits 0, and leaves ZOXIDE_FIXTURE unset' \
  0 unset '' 0 '[oh-my-zsh] zoxide not found, please install it from https://github.com/ajeetdsouza/zoxide' '' '__UNSET__'

print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
