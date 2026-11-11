#!/usr/bin/env zsh
# Fixture test for the history plugin. Runs in a private sandbox and calls no real pager.
# Usage: zsh -f plugins/history/tests/history.test.zsh [path/to/history.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/history.plugin.zsh}
readme=${0:A:h:h}/README.md
test_dir=$(mktemp -d) || exit 1
orig_path=($path)
trap 'path=($orig_path); command rm -rf -- "$test_dir"' EXIT

# Sandbox: private HOME, ZDOTDIR, ZSH_CACHE_DIR, and a PATH holding only our stubs.
export HOME=$test_dir/home ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export STUB_LOG=$test_dir/args.log REAL_GREP=${commands[grep]} REAL_CAT=${commands[cat]}
command mkdir -p -- "$HOME" "$ZDOTDIR" "$ZSH_CACHE_DIR" "$test_dir/bin"

if [[ -z $REAL_GREP || -z $REAL_CAT ]]; then
  print -u2 -r -- "FAIL: missing required system utility (grep or cat)"
  exit 1
fi

# Stubs: log the argument count and one argument per line, then behave predictably.
command cat >| "$test_dir/bin/grep" <<'STUB'
#!/bin/sh
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
exec "$REAL_GREP" "$@"
STUB
command cat >| "$test_dir/bin/less" <<'STUB'
#!/bin/sh
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
exec "$REAL_CAT"
STUB
command chmod 0755 "$test_dir/bin/grep" "$test_dir/bin/less" || exit 1
path=($test_dir/bin)

# Extract tagged fenced code blocks directly from plugins/history/README.md so docs cannot drift.
readme_text=$(<"$readme") || exit 1
extract_block() {
  local tag=$1
  local start_marker="<!-- history-example:${1}:start -->"
  local end_marker="<!-- history-example:${1}:end -->"
  local section body
  if [[ $readme_text != *"$start_marker"*"$end_marker"* ]]; then
    print -u2 -r -- "FAIL: missing README marker block: $tag"
    exit 1
  fi
  section=${readme_text#*"$start_marker"}
  section=${section%%"$end_marker"*}
  body=${section#*$'\n```'}
  body=${body#*$'\n'}
  body=${body%$'\n```'*}
  REPLY=$body
}

extract_block setup; readme_setup=$REPLY
extract_block command; readme_cmd=$REPLY
extract_block output; readme_output=$REPLY
extract_block verify; readme_verify=$REPLY
extract_block verify-output; readme_verify_output=$REPLY

source "$plugin" || exit 1

typeset -i tests=0 failures=0

check() {
  # check <success|edge> <description> <expected_status> <expected_stdout> <expected_stderr> <expected_args> <command>
  local kind=$1 description=$2 expected_status=$3 expected_stdout=$4 expected_stderr=$5 expected_args=$6 cmd=$7
  local actual_stdout actual_stderr actual_status actual_args state_before state_after
  local -i before_count after_count

  : >| "$STUB_LOG"
  state_before=$(fc -l 1 2>/dev/null || true)
  before_count=${#${(f)state_before}}

  eval "$cmd" >| "$test_dir/stdout" 2>| "$test_dir/stderr"
  actual_status=$?
  actual_stdout=$(<"$test_dir/stdout")
  actual_stderr=$(<"$test_dir/stderr")
  actual_args=$(<"$STUB_LOG")

  state_after=$(fc -l 1 2>/dev/null || true)
  after_count=${#${(f)state_after}}

  (( tests++ ))
  if [[ $actual_status == $expected_status \
     && $actual_stdout == "$expected_stdout" \
     && $actual_stderr == "$expected_stderr" \
     && $actual_args == "$expected_args" \
     && $state_before == "$state_after" ]]; then
    print -r -- "PASS: [$kind] $description"
  else
    print -r -- "FAIL: [$kind] $description"
    (( failures++ ))
  fi
  print -r -- "  status: $actual_status (expected $expected_status)"
  print -r -- "  stdout: ${(qqq)actual_stdout} (expected ${(qqq)expected_stdout})"
  print -r -- "  stderr: ${(qqq)actual_stderr} (expected ${(qqq)expected_stderr})"
  print -r -- "  args:   ${(j: | :)${(f)actual_args}} (expected ${(j: | :)${(f)expected_args}})"
  print -r -- "  state:  history_events_before=$before_count history_events_after=$after_count"
}

# Verify initial empty history before running the README setup block.
initial_history=$(fc -l 1 2>/dev/null || true)
if [[ -n $initial_history ]]; then
  print -u2 -r -- "FAIL: expected empty initial history before setup"
  exit 1
fi

eval "$readme_setup" || exit 1
seeded_history=$(fc -l 1 2>/dev/null || true)

check success \
  'README example command output matches README output block' \
  0 \
  "$readme_output" \
  '' \
  $'argc=1\narg=git' \
  "$readme_cmd"

check success \
  'README state verification h lists all three setup events unchanged' \
  0 \
  "$readme_verify_output" \
  '' \
  '' \
  "$readme_verify"

check success \
  'hl pipes full history into less stub with zero arguments' \
  0 \
  "$readme_verify_output" \
  '' \
  'argc=0' \
  'hl'

check success \
  'hsi searches history case-insensitively with grep -i' \
  0 \
  "$readme_output" \
  '' \
  $'argc=2\narg=-i\narg=GIT' \
  'hsi GIT'

check edge \
  'hs with no matching event prints nothing, returns 1, and preserves history' \
  1 \
  '' \
  '' \
  $'argc=1\narg=no-such-command' \
  'hs no-such-command'

print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
