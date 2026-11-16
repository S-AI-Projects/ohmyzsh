#!/usr/bin/env zsh

emulate -LR zsh
setopt aliases

local repo_root=${1:-${0:A:h:h:h}}
repo_root=${repo_root:A}
local test_dir=$(mktemp -d) || exit 1
trap 'command rm -rf -- "$test_dir"' EXIT
local zdotdir="$test_dir/zdotdir" stub_dir="$test_dir/bin" fixture="$test_dir/app"
mkdir -p "$zdotdir" "$stub_dir" "$fixture" "$fixture/bin"
export ZDOTDIR="$zdotdir" ZSH="$repo_root" COMMAND_LOG="$test_dir/argv.log"

cat > "$stub_dir/command-stub" <<'STUB'
#!/bin/zsh
print -r -- "${0:t}" >> "$COMMAND_LOG"
for arg in "$@"; do
  printf '%s\n' "${(qqq)arg}" >> "$COMMAND_LOG"
done
print -r -- "stub-output:${0:t}"
exit "${STUB_STATUS:-0}"
STUB
chmod +x "$stub_dir/command-stub"
for name in rake tail ruby bundle; do
  ln -s command-stub "$stub_dir/$name"
done

# Local application binstub for rails
cat > "$fixture/bin/rails" <<'LOCAL_STUB'
#!/bin/zsh
print -r -- "local-rails" >> "$COMMAND_LOG"
for arg in "$@"; do
  printf '%s\n' "${(qqq)arg}" >> "$COMMAND_LOG"
done
print -r -- "stub-output:local-rails"
exit "${STUB_STATUS:-0}"
LOCAL_STUB
chmod +x "$fixture/bin/rails"

export PATH="$stub_dir:/usr/bin:/bin:/usr/sbin:/sbin"
rehash

# Explicit isolated plugin bootstrap; no user startup files or live Rails services.
setopt interactivecomments
fpath=("$ZSH/plugins/rails" $fpath)
autoload -Uz compinit
compinit -D -d "$zdotdir/.zcompdump"
# The plugin registers completion for the rails/rake commands. Completion itself
# is outside these wrapper tests, so make registration harmless in this harness.
compdef() { : }
source "$ZSH/plugins/rails/rails.plugin.zsh"

local -i tests=0 failures=0 exit_code
local output expected_log before after

record_result() {
  local name=$1 expected_output=$2 expected_status=$3 expected_args=$4 actual_args
  output=$(< "$test_dir/output")
  exit_code=$(< "$test_dir/status")
  actual_args=$(< "$COMMAND_LOG")
  (( tests++ ))
  if [[ "$output" == "$expected_output" && "$exit_code" == "$expected_status" && "$actual_args" == "$expected_args" ]]; then
    print -r -- "PASS: $name | output=${(qqq)output} | status=$exit_code | argv=${(qqq)actual_args}"
  else
    print -u2 -r -- "FAIL: $name"
    print -u2 -r -- "  expected output=${(qqq)expected_output}, status=$expected_status, argv=${(qqq)expected_args}"
    print -u2 -r -- "  actual output=${(qqq)output}, status=$exit_code, argv=${(qqq)actual_args}"
    (( failures++ ))
  fi
}

# Ordinary success: local Rails executable preserves each argument, including spaces.
cd "$fixture"
: >| "$COMMAND_LOG"
before=$(command find "$fixture" -print | LC_ALL=C sort)
eval "rails routes --grep 'admin routes'" >| "$test_dir/output" 2>&1
exit_code=$?
printf '%s' "$exit_code" >| "$test_dir/status"
after=$(command find "$fixture" -print | LC_ALL=C sort)
expected_log=$'local-rails\n"routes"\n"--grep"\n"admin routes"'
record_result 'rails local executable ordinary success' 'stub-output:local-rails' '0' "$expected_log"
if [[ "$before" == "$after" ]]; then
  print -r -- "PASS: rails repository state unchanged | before=${(qqq)before} | after=${(qqq)after}"
else
  print -u2 -r -- "FAIL: rails repository state changed | before=${(qqq)before} | after=${(qqq)after}"
  (( failures++ ))
fi

# Supported missing-project edge: with no Gemfile/bin/rake, rake falls back to PATH.
: >| "$COMMAND_LOG"
before=$(command find "$fixture" -print | LC_ALL=C sort)
eval "rake -T" >| "$test_dir/output" 2>&1
exit_code=$?
printf '%s' "$exit_code" >| "$test_dir/status"
after=$(command find "$fixture" -print | LC_ALL=C sort)
expected_log=$'rake\n"-T"'
record_result 'rake missing-Gemfile edge' 'stub-output:rake' '0' "$expected_log"
if [[ "$before" == "$after" ]]; then
  print -r -- "PASS: rake missing-project state unchanged | before=${(qqq)before} | after=${(qqq)after}"
else
  print -u2 -r -- "FAIL: rake missing-project state changed | before=${(qqq)before} | after=${(qqq)after}"
  (( failures++ ))
fi

# Empty-args and failure status propagation: empty string is preserved and exit status returned.
: >| "$COMMAND_LOG"
export STUB_STATUS=7
eval 'rails ""' >| "$test_dir/output" 2>&1
exit_code=$?
printf '%s' "$exit_code" >| "$test_dir/status"
unset STUB_STATUS
expected_log=$'local-rails\n""'
record_result 'rails empty-args failure status propagation' 'stub-output:local-rails' '7' "$expected_log"

# devlog is only expanded to tail; the stub prevents any real follow operation.
: >| "$COMMAND_LOG"
eval "devlog" >| "$test_dir/output" 2>&1
exit_code=$?
printf '%s' "$exit_code" >| "$test_dir/status"
expected_log=$'tail\n"-f"\n"log/development.log"'
record_result 'devlog alias expansion' 'stub-output:tail' '0' "$expected_log"

print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
