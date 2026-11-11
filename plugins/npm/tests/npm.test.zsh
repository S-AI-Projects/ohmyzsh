#!/usr/bin/env zsh
# Fixture test for the npm plugin. Runs in a private sandbox and never calls real npm.
# Usage: zsh -f plugins/npm/tests/npm.test.zsh [path/to/npm.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/npm.plugin.zsh}
test_dir=$(mktemp -d "${${TMPDIR:-/tmp}%/}/npm-test.XXXXXX") || exit 1
orig_path=($path)
trap 'path=($orig_path); command rm -rf -- "$test_dir"' EXIT

export HOME=$test_dir/home ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export STUB_LOG=$test_dir/args.log
REAL_RM=${commands[rm]}

if [[ -z $REAL_RM ]]; then
  print -u2 -r -- 'FAIL: missing required system utility (rm)'
  exit 1
fi

command mkdir -p -- "$HOME" "$ZDOTDIR" "$ZSH_CACHE_DIR" "$test_dir/bin" "$test_dir/no_npm_bin"
command ln -s -- "$REAL_RM" "$test_dir/bin/rm"
command ln -s -- "$REAL_RM" "$test_dir/no_npm_bin/rm"

command cat >| "$test_dir/bin/npm" <<'STUB'
#!/bin/sh
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
exit 0
STUB
command chmod 0755 "$test_dir/bin/npm" || exit 1

autoload -Uz compinit && compinit -D || exit 1
initial_npm_comp=${_comps[npm]:-__UNSET__}

typeset -i tests=0 failures=0

# Case 1: npm present -> stale cache file is removed and _comps[npm] becomes _npm_completion.
stale_file="$ZSH_CACHE_DIR/npm_completion"
: >| "$stale_file"
cache_before_exists=$([[ -e $stale_file ]] && echo yes || echo no)
case1_out=$(
  path=($test_dir/bin)
  source "$plugin" || exit 1
  print -r -- "comp=${_comps[npm]:-__UNSET__}|stale=$([[ -e $stale_file ]] && echo yes || echo no)|npmg=${+aliases[npmg]}"
)
case1_status=$?
(( tests++ ))
if [[ $case1_status == 0 && $case1_out == 'comp=_npm_completion|stale=no|npmg=1' ]]; then
  print -r -- 'PASS: [success] when npm is present, stale cache file is deleted and _npm_completion is registered'
else
  print -r -- 'FAIL: [success] when npm is present, stale cache file is deleted and _npm_completion is registered'
  (( failures++ ))
fi
print -r -- "  status: $case1_status (expected 0)"
print -r -- "  state:  stale_before=$cache_before_exists result=${(qqq)case1_out}"

# Case 2: no npm on PATH -> _comps[npm] stays untouched, stale cache file survives, aliases still defined.
: >| "$stale_file"
cache_before_exists=$([[ -e $stale_file ]] && echo yes || echo no)
case2_out=$(
  path=($test_dir/no_npm_bin)
  source "$plugin" || exit 1
  print -r -- "comp=${_comps[npm]:-__UNSET__}|stale=$([[ -e $stale_file ]] && echo yes || echo no)|npmg=${aliases[npmg]:-}|npmS=${aliases[npmS]:-}|npmD=${aliases[npmD]:-}"
)
case2_status=$?
(( tests++ ))
if [[ $case2_status == 0 \
   && $case2_out == "comp=${initial_npm_comp}|stale=yes|npmg=npm i -g |npmS=npm i -S |npmD=npm i -D " ]]; then
  print -r -- 'PASS: [edge] when npm is missing, completion is skipped, cache file is kept, and aliases remain defined'
else
  print -r -- 'FAIL: [edge] when npm is missing, completion is skipped, cache file is kept, and aliases remain defined'
  (( failures++ ))
fi
print -r -- "  status: $case2_status (expected 0)"
print -r -- "  state:  initial_comp=${(qqq)initial_npm_comp} stale_before=$cache_before_exists result=${(qqq)case2_out}"

# Case 3: npmD, npmS, and npmg forward exact flags, quoted args, and trailing-space alias expansion.
: >| "$STUB_LOG"
case3_status=$(
  path=($test_dir/bin)
  source "$plugin" || exit 1
  alias pk='left-pad'
  eval 'npmD jest "my pkg" && npmS react && npmg typescript && npmg pk'
  print -r -- $?
)
actual_args=$(<"$STUB_LOG")
expected_args=$'argc=4\narg=i\narg=-D\narg=jest\narg=my pkg\nargc=3\narg=i\narg=-S\narg=react\nargc=3\narg=i\narg=-g\narg=typescript\nargc=3\narg=i\narg=-g\narg=left-pad'
(( tests++ ))
if [[ $case3_status == 0 && $actual_args == "$expected_args" ]]; then
  print -r -- 'PASS: [success] npmD, npmS, and npmg preserve flags, quoted arguments, and trailing-space alias expansion'
else
  print -r -- 'FAIL: [success] npmD, npmS, and npmg preserve flags, quoted arguments, and trailing-space alias expansion'
  (( failures++ ))
fi
print -r -- "  status: $case3_status (expected 0)"
print -r -- "  args:   ${(j: | :)${(f)actual_args}}"

print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
