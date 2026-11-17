#!/usr/bin/env zsh

emulate -LR zsh

local case_name=$1
local repo_root=${2:A}
local work_dir=${3:A}
local completion_file="$ZSH_CACHE_DIR/completions/_asdf"
local before_state after_state completion_contents command_log actual_data_dir asdf_exit_status
local -i source_status=0 tries=0 shim_count=0
local path_entry

export ZDOTDIR="$ASDF_TEST_ROOT/zdotdir" ZSH="$repo_root"
export ASDF_TEST_UNRELATED='preserve-this-value'
cd "$work_dir" || exit 1
typeset -g -A _comps
_comps=()

state() {
  local comp_value='<unset>' completion_state='absent'
  [[ -n ${ASDF_DATA_DIR-} ]] && actual_data_dir=$ASDF_DATA_DIR || actual_data_dir='<unset>'
  (( ${+_comps[asdf]} )) && comp_value=$_comps[asdf]
  [[ -f "$completion_file" ]] && completion_state='present'
  print -r -- "ASDF_DATA_DIR=$actual_data_dir"
  print -r -- "PATH=${(j/:/)path}"
  print -r -- "PWD=$PWD"
  print -r -- "asdf_completion_mapping=$comp_value"
  print -r -- "completion_file=$completion_state"
  print -r -- "unrelated=$ASDF_TEST_UNRELATED"
}

before_state=$(state)
source "$ZSH/plugins/asdf/asdf.plugin.zsh"
source_status=$?

if [[ "$case_name" == success ]]; then
  zmodload zsh/zselect
  while [[ ! -f "$completion_file" && $tries -lt 100 ]]; do
    (( tries++ ))
    zselect -t 1
  done
fi

after_state=$(state)
[[ -f "$completion_file" ]] && completion_contents=$(< "$completion_file") || completion_contents='<absent>'
[[ -f "$ASDF_TEST_LOG" ]] && command_log=$(< "$ASDF_TEST_LOG") || command_log='<no invocation>'
if [[ "$command_log" == '<no invocation>' ]]; then
  asdf_exit_status='not-run'
else
  asdf_exit_status=${${(f)command_log}[-1]#EXIT:}
fi

case "$case_name" in
  success)
    for path_entry in $path; do
      [[ "$path_entry" == "$ASDF_DATA_DIR/shims" ]] && (( shim_count++ ))
    done
    if [[ $source_status != 0 || "$ASDF_DATA_DIR" != "$HOME/.asdf" || \
          "$path[1]" != "$ASDF_DATA_DIR/shims" || \
          $shim_count != 1 || \
          "${_comps[asdf]-}" != _asdf || \
          "$completion_contents" != '#compdef asdf' || \
          "$command_log" != $'COUNT:2\n"completion"\n"zsh"\nEXIT:0' || \
          "$asdf_exit_status" != 0 || \
          "$PWD" != "$work_dir" || "$ASDF_TEST_UNRELATED" != 'preserve-this-value' ]]; then
      print -u2 -r -- "FAIL: success initialization | source_status=$source_status | asdf_status=$asdf_exit_status | state_before=${(qqq)before_state} | state_after=${(qqq)after_state} | argv=${(qqq)command_log} | completion=${(qqq)completion_contents}"
      exit 1
    fi
    ;;
  missing-dependency)
    if [[ $source_status != 0 || -n ${ASDF_DATA_DIR-} || "$PATH" != "$ASDF_TEST_INITIAL_PATH" || \
          -n "${_comps[asdf]-}" || -f "$completion_file" || \
          "$command_log" != '<no invocation>' || "$asdf_exit_status" != 'not-run' || "$PWD" != "$work_dir" || \
          "$ASDF_TEST_UNRELATED" != 'preserve-this-value' ]]; then
      print -u2 -r -- "FAIL: missing dependency early return | source_status=$source_status | asdf_status=$asdf_exit_status | state_before=${(qqq)before_state} | state_after=${(qqq)after_state} | argv=${(qqq)command_log}"
      exit 1
    fi
    ;;
  *)
    print -u2 -r -- "Unknown test case: $case_name"
    exit 2
    ;;
esac

print -r -- "PASS: $case_name | source_status=$source_status | asdf_status=$asdf_exit_status | state_before=${(qqq)before_state} | state_after=${(qqq)after_state} | argv=${(qqq)command_log} | completion=${(qqq)completion_contents}"
