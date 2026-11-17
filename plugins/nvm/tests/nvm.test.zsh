#!/usr/bin/env zsh

emulate -LR zsh

local case_name=$1
local repo_root=${2:A}
local fixture="$NVM_TEST_ROOT/$case_name"
local zdotdir="$fixture/zdotdir"
local stub_dir="$fixture/bin"
local nvm_dir="$fixture/nvm"
local before_state after_state output expected_args actual_args
local -i exit_code=0 failures=0

mkdir -p "$zdotdir" "$stub_dir" "$nvm_dir"
export ZDOTDIR="$zdotdir" ZSH="$repo_root" NVM_DIR="$nvm_dir"
export NVM_TEST_LOG="$fixture/argv.log"
export NVM_TEST_LOAD_MARKER="$fixture/nvm-loaded"
export NVM_TEST_COMPLETION_MARKER="$fixture/completion-loaded"
export PATH="$stub_dir:/usr/bin:/bin:/usr/sbin:/sbin"
rehash

cat > "$NVM_DIR/nvm.sh" <<'NVM_STUB'
print -r -- loaded >| "$NVM_TEST_LOAD_MARKER"
nvm() {
  print -r -- "COMMAND:nvm" >| "$NVM_TEST_LOG"
  print -r -- "COUNT:$#" >> "$NVM_TEST_LOG"
  for arg in "$@"; do print -r -- "${(qqq)arg}" >> "$NVM_TEST_LOG"; done
  print -r -- nvm-output
  return "${NVM_TEST_STATUS:-0}"
}
NVM_STUB
cat > "$NVM_DIR/bash_completion" <<'COMPLETION_STUB'
print -r -- loaded >| "$NVM_TEST_COMPLETION_MARKER"
COMPLETION_STUB
cat > "$stub_dir/custom_tool" <<'COMMAND_STUB'
#!/bin/zsh
print -r -- "COMMAND:custom_tool" >| "$NVM_TEST_LOG"
print -r -- "COUNT:$#" >> "$NVM_TEST_LOG"
for arg in "$@"; do print -r -- "${(qqq)arg}" >> "$NVM_TEST_LOG"; done
print -r -- custom-output
exit "${CUSTOM_TOOL_STATUS:-0}"
COMMAND_STUB
chmod +x "$stub_dir/custom_tool"

state() {
  local loaded=0 completion=0
  [[ -f "$NVM_TEST_LOAD_MARKER" ]] && loaded=1
  [[ -f "$NVM_TEST_COMPLETION_MARKER" ]] && completion=1
  print -r -- "nvm_loaded=$loaded,completion_loaded=$completion"
}

# The real plugin uses compinit/bashcompinit while loading nvm completion.
autoload -Uz compinit
compinit -D -d "$zdotdir/.zcompdump"
case "$case_name" in
  minimum)
    zstyle ':omz:plugins:nvm' lazy yes
    ;;
  optional)
    zstyle ':omz:plugins:nvm' lazy yes
    zstyle ':omz:plugins:nvm' lazy-cmd custom_tool
    ;;
  invalid-combination)
    # README documents lazy-cmd as an option used together with lazy startup.
    zstyle ':omz:plugins:nvm' lazy-cmd custom_tool
    ;;
  *)
    print -u2 -r -- "Unknown test case: $case_name"
    exit 2
    ;;
esac

before_state=$(state)
source "$ZSH/plugins/nvm/nvm.plugin.zsh"

case "$case_name" in
  minimum)
    if [[ -f "$NVM_TEST_LOAD_MARKER" || ! -functions[nvm] ]]; then
      print -u2 -r -- 'FAIL: minimum lazy trigger was not deferred'
      exit 1
    fi
    : >| "$NVM_TEST_LOG"
    output=$(nvm)
    exit_code=$?
    expected_args=$'COMMAND:nvm\nCOUNT:0'
    actual_args=$(< "$NVM_TEST_LOG")
    after_state=$(state)
    if [[ "$output" != nvm-output || $exit_code != 0 || "$actual_args" != "$expected_args" || "$after_state" != 'nvm_loaded=1,completion_loaded=1' ]]; then
      print -u2 -r -- "FAIL: minimum lazy trigger | output=${(qqq)output} | status=$exit_code | argv=${(qqq)actual_args} | state_before=$before_state | state_after=$after_state"
      exit 1
    fi
    print -r -- "PASS: nvm minimum lazy trigger | output=${(qqq)output} | status=$exit_code | argv=${(qqq)actual_args} | state_before=$before_state | state_after=$after_state"
    ;;
  optional)
    if [[ -f "$NVM_TEST_LOAD_MARKER" || ! -functions[custom_tool] ]]; then
      print -u2 -r -- 'FAIL: optional lazy command was not registered'
      exit 1
    fi
    : >| "$NVM_TEST_LOG"
    output=$(custom_tool --version 'two words')
    exit_code=$?
    expected_args=$'COMMAND:custom_tool\nCOUNT:2\n"--version"\n"two words"'
    actual_args=$(< "$NVM_TEST_LOG")
    after_state=$(state)
    if [[ "$output" != custom-output || $exit_code != 0 || "$actual_args" != "$expected_args" || "$after_state" != 'nvm_loaded=1,completion_loaded=1' ]]; then
      print -u2 -r -- "FAIL: optional lazy command arguments | output=${(qqq)output} | status=$exit_code | argv=${(qqq)actual_args} | state_before=$before_state | state_after=$after_state"
      exit 1
    fi
    print -r -- "PASS: nvm optional lazy command argument | output=${(qqq)output} | status=$exit_code | argv=${(qqq)actual_args} | state_before=$before_state | state_after=$after_state"
    ;;
  invalid-combination)
    after_state=$(state)
    if [[ "$after_state" != 'nvm_loaded=1,completion_loaded=1' ]] || (( $+functions[custom_tool] )); then
      print -u2 -r -- "FAIL: lazy-cmd without lazy | state_before=$before_state | state_after=$after_state | custom_tool_function=$+functions[custom_tool]"
      exit 1
    fi
    print -r -- "PASS: documented invalid combination (lazy-cmd without lazy) | output=none | status=0 | argv=none | state_before=$before_state | state_after=$after_state"
    ;;
esac
