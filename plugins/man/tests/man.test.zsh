#!/usr/bin/env zsh

emulate -LR zsh

local case_name=$1
local repo_root=${2:A}
local work_dir=${3:A}
local -a args
local buffer_before buffer_after argv_after state_before state_after output
local -i widget_status=0 command_status=0

export ZDOTDIR="$ANT_TEST_ROOT/zdotdir" ZSH="$repo_root"
export ANT_TEST_LOG="$ANT_TEST_ROOT/man-argv.log"
cd "$work_dir" || exit 1

state() {
  local entry
  print -r -- "PWD=$PWD"
  for entry in *(N); do
    if [[ -d "$entry" ]]; then
      print -r -- "DIR:${(qqq)entry}"
      local nested
      for nested in "$entry"/*(N); do
        print -r -- "FILE:${(qqq)nested:t}:$(<"$nested")"
      done
    else
      print -r -- "FILE:${(qqq)entry}:$(<"$entry")"
    fi
  done
}

# The widget only needs these ZLE registration calls while running in this
# non-interactive fixture. Its actual command lookup uses the PATH stub.
zle() { return 0 }
bindkey() { return 0 }
source "$ZSH/plugins/man/man.plugin.zsh"

case "$case_name" in
  matched-wildcard)
    buffer_before='viewer "manual files/*.md"'
    BUFFER=$buffer_before
    ;;
  unmatched-wildcard)
    buffer_before='viewer "manual files/no-match*.md"'
    BUFFER=$buffer_before
    ;;
  *)
    print -u2 -r -- "Unknown test case: $case_name"
    exit 2
    ;;
esac

state_before=$(state)
: >| "$ANT_TEST_LOG"
man-command-line
widget_status=$?
buffer_after=$BUFFER
output=$(eval "$BUFFER")
command_status=$?
argv_after=$(< "$ANT_TEST_LOG")
state_after=$(state)

local expected_log expected_buffer
case "$case_name" in
  matched-wildcard)
    expected_buffer='man viewer manual\ files/\*.md'
    expected_log=$'BEGIN\nCOUNT:1\n"viewer-manual files/*.md"\nBEGIN\nCOUNT:2\n"viewer"\n"manual files/*.md"'
    ;;
  unmatched-wildcard)
    expected_buffer='man viewer manual\ files/no-match\*.md'
    expected_log=$'BEGIN\nCOUNT:1\n"viewer-manual files/no-match*.md"\nBEGIN\nCOUNT:2\n"viewer"\n"manual files/no-match*.md"'
    ;;
esac

if [[ "$buffer_after" != "$expected_buffer" || $widget_status != 0 || \
      $command_status != 0 || "$output" != 'stub-man-output' || \
      "$argv_after" != "$expected_log" || "$state_before" != "$state_after" ]]; then
  print -u2 -r -- "FAIL: $case_name | widget_status=$widget_status | command_status=$command_status | output=${(qqq)output} | BUFFER_before=${(qqq)buffer_before} | BUFFER_after=${(qqq)buffer_after} | argv=${(qqq)argv_after} | state_before=${(qqq)state_before} | state_after=${(qqq)state_after}"
  exit 1
fi

print -r -- "PASS: $case_name | widget_status=$widget_status | command_status=$command_status | output=${(qqq)output} | BUFFER_before=${(qqq)buffer_before} | BUFFER_after=${(qqq)buffer_after} | argv=${(qqq)argv_after} | state_before=${(qqq)state_before} | state_after=${(qqq)state_after}"
