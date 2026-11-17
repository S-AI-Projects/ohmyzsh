#!/usr/bin/env zsh

emulate -LR zsh

local case_name=$1
local repo_root=${2:A}
local before_ant_args after_ant_args before_unrelated after_unrelated
local -i exit_code=0

export ZDOTDIR="$ANT_TEST_ROOT/zdotdir" ZSH="$repo_root"
mkdir -p "$ZDOTDIR"
export ANT_TEST_UNRELATED='keep-this-value'

if (( ${+ANT_ARGS} )); then
  before_ant_args=$ANT_ARGS
else
  before_ant_args='<unset>'
fi
before_unrelated=$ANT_TEST_UNRELATED

source "$ZSH/plugins/ant/ant.plugin.zsh"
exit_code=$?

if (( ${+ANT_ARGS} )); then
  after_ant_args=$ANT_ARGS
else
  after_ant_args='<unset>'
fi
after_unrelated=$ANT_TEST_UNRELATED

case "$case_name" in
  default)
    if [[ "$after_ant_args" != '-logger org.apache.tools.ant.listener.AnsiColorLogger' ]]; then
      print -u2 -r -- "FAIL: default Ant args | exit=$exit_code | ANT_ARGS_before=${(qqq)before_ant_args} | ANT_ARGS_after=${(qqq)after_ant_args}"
      exit 1
    fi
    ;;
  preserve-custom)
    if [[ "$after_ant_args" != "$before_ant_args" || -z "$before_ant_args" ]]; then
      print -u2 -r -- "FAIL: preserve custom Ant args | exit=$exit_code | ANT_ARGS_before=${(qqq)before_ant_args} | ANT_ARGS_after=${(qqq)after_ant_args}"
      exit 1
    fi
    ;;
  *)
    print -u2 -r -- "Unknown test case: $case_name"
    exit 2
    ;;
esac

if [[ "$after_unrelated" != "$before_unrelated" || "$after_unrelated" != 'keep-this-value' ]]; then
  print -u2 -r -- "FAIL: unrelated shell state changed | exit=$exit_code | unrelated_before=${(qqq)before_unrelated} | unrelated_after=${(qqq)after_unrelated}"
  exit 1
fi

print -r -- "PASS: $case_name | exit=$exit_code | ANT_ARGS_before=${(qqq)before_ant_args} | ANT_ARGS_after=${(qqq)after_ant_args} | unrelated_before=${(qqq)before_unrelated} | unrelated_after=${(qqq)after_unrelated}"
