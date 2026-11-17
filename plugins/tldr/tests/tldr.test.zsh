#!/usr/bin/env zsh

typeset -ga TEST_ZLE_CALLS TEST_BINDKEY_CALLS

zle() {
  TEST_ZLE_CALLS+=("$*")
  if [[ $1 == up-history ]]; then
    BUFFER=$TLDR_HISTORY_BUFFER
  fi
}

bindkey() {
  TEST_BINDKEY_CALLS+=("$*")
}

source "$TLDR_PLUGIN_FILE"

BUFFER=$TLDR_INPUT_BUFFER
before_buffer=$BUFFER
before_pwd=$PWD
before_path=$PATH
tldr-command-line
function_status=$?
after_buffer=$BUFFER
after_pwd=$PWD
after_path=$PATH

print -r -- "case=$TLDR_TEST_CASE"
print -r -- "function_status=$function_status"
print -r -- "before_buffer=$before_buffer"
print -r -- "after_buffer=$after_buffer"
print -r -- "before_pwd=$before_pwd"
print -r -- "after_pwd=$after_pwd"
print -r -- "before_path=$before_path"
print -r -- "after_path=$after_path"
print -r -- "zle_calls=${(j:|:)TEST_ZLE_CALLS}"
print -r -- "bindkey_calls=${(j:|:)TEST_BINDKEY_CALLS}"

[[ $function_status -eq 0 ]] || exit 40
[[ $after_buffer == "$TLDR_EXPECTED_BUFFER" ]] || {
  print -u2 -r -- "BUFFER assertion failed: expected ${(qqq)TLDR_EXPECTED_BUFFER}, got ${(qqq)after_buffer}"
  exit 42
}
[[ $before_pwd == $after_pwd && $before_path == $after_path ]] || exit 43
[[ ${TEST_ZLE_CALLS[1]} == '-N tldr-command-line' ]] || exit 44
[[ ${#TEST_BINDKEY_CALLS[@]} -eq 1 ]] || exit 45
