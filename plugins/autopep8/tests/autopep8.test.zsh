#!/usr/bin/env zsh

emulate -LR zsh

local case_name=$1
local repo_root=${2:A}
local work_dir=${3:A}
local -i completion_status=0
local specs_before specs_after

export ZDOTDIR="$AUTOPEP8_TEST_ROOT/zdotdir" ZSH="$repo_root"
export AUTOPEP8_TEST_LOG="$AUTOPEP8_TEST_ROOT/arguments.log"
cd "$work_dir" || exit 1

_arguments() {
  print -r -- "COUNT:$#" >| "$AUTOPEP8_TEST_LOG"
  local argument
  for argument in "$@"; do
    print -r -- "${(qqq)argument}" >> "$AUTOPEP8_TEST_LOG"
  done
  return "$AUTOPEP8_ARGUMENTS_STATUS"
}

_autopep8() {
  source "$ZSH/plugins/autopep8/_autopep8"
}

state() {
  print -r -- "PWD=$PWD"
  print -r -- "PATH=$PATH"
  print -r -- "ZDOTDIR=$ZDOTDIR"
  print -r -- "HOME=$HOME"
}

specs_before=$(state)
_autopep8
completion_status=$?
specs_after=$(state)

if [[ "$case_name" == success ]]; then
  if [[ $completion_status != 0 || "$specs_before" != "$specs_after" ]]; then
    print -u2 -r -- "FAIL: completion success | status=$completion_status | state_before=${(qqq)specs_before} | state_after=${(qqq)specs_after}"
    exit 1
  fi
elif [[ "$case_name" == argument-error ]]; then
  if [[ $completion_status != 37 || "$specs_before" != "$specs_after" ]]; then
    print -u2 -r -- "FAIL: completion status propagation | status=$completion_status | state_before=${(qqq)specs_before} | state_after=${(qqq)specs_after}"
    exit 1
  fi
else
  print -u2 -r -- "Unknown test case: $case_name"
  exit 2
fi

print -r -- "PASS: $case_name | exit_status=$completion_status | state_before=${(qqq)specs_before} | state_after=${(qqq)specs_after}"
