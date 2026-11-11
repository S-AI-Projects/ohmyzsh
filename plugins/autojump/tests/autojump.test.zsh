#!/usr/bin/env zsh
# Fixture test for the autojump plugin. Tests quoting with spaces and glob characters.
# Usage: zsh -f plugins/autojump/tests/autojump.test.zsh [path/to/autojump.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/autojump.plugin.zsh}
test_dir=$(mktemp -d "${${TMPDIR:-/tmp}%/}/autojump-test.XXXXXX") || exit 1
test_dir=${test_dir:A}
orig_path=($path)
trap 'path=($orig_path); command rm -rf -- "$test_dir"' EXIT

export ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export STUB_LOG=$test_dir/args.log

spaced_home="$test_dir/home dir [x]*"
decoy_home="$test_dir/home dir xdecoy"
empty_home="$test_dir/empty dir [z]*"
brew_prefix="$test_dir/brew prefix [y]*"
export BREW_PREFIX_FIXTURE="$brew_prefix"

command mkdir -p -- \
  "$ZDOTDIR" "$ZSH_CACHE_DIR" "$test_dir/bin" "$test_dir/empty_bin" \
  "$spaced_home/.autojump/etc/profile.d" \
  "$decoy_home/.autojump/etc/profile.d" \
  "$empty_home" \
  "$brew_prefix/etc/profile.d"

expected_home_script="$spaced_home/.autojump/etc/profile.d/autojump.zsh"
decoy_script="$decoy_home/.autojump/etc/profile.d/autojump.zsh"
expected_brew_script="$brew_prefix/etc/profile.d/autojump.sh"

print -r -- "AUTOJUMP_MARKER=${(qqq)expected_home_script}" >| "$expected_home_script"
print -r -- 'AUTOJUMP_DECOY=hit' >| "$decoy_script"
decoy_snapshot=$(<"$decoy_script")
print -r -- "AUTOJUMP_BREW_MARKER=${(qqq)expected_brew_script}" >| "$expected_brew_script"

command cat >| "$test_dir/bin/brew" <<'STUB'
#!/bin/sh
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
printf '%s\n' "$BREW_PREFIX_FIXTURE"
STUB
command chmod 0755 "$test_dir/bin/brew" || exit 1

typeset -i tests=0 failures=0

# Case 1: HOME with spaces and glob metacharacters loads exact fixture and leaves decoy untouched.
: >| "$STUB_LOG"
out1=$(
  export HOME="$spaced_home"
  unset AUTOJUMP_MARKER AUTOJUMP_DECOY found file autojump_paths
  path=($test_dir/empty_bin)
  source "$plugin" >| "$test_dir/c1_stdout" 2>| "$test_dir/c1_stderr"
  st=$?
  print -r -- "st=$st|marker=${AUTOJUMP_MARKER:-__UNSET__}|decoy=${+AUTOJUMP_DECOY}|leaked=${+autojump_paths},${+file},${+found}"
)
c1_stdout=$(<"$test_dir/c1_stdout")
c1_stderr=$(<"$test_dir/c1_stderr")
decoy_after=$(<"$decoy_script")
(( tests++ ))
if [[ $out1 == "st=0|marker=${expected_home_script}|decoy=0|leaked=0,0,0" \
   && -z $c1_stdout && -z $c1_stderr && $decoy_after == "$decoy_snapshot" ]]; then
  print -r -- 'PASS: [success] HOME containing spaces and [x]* sources exact autojump.zsh without touching decoy'
else
  print -r -- 'FAIL: [success] HOME containing spaces and [x]* sources exact autojump.zsh without touching decoy'
  (( failures++ ))
fi
print -r -- "  result: ${${out1//$test_dir/<sandbox>}}"
print -r -- "  stdout: ${(qqq)c1_stdout} stderr: ${(qqq)${c1_stderr//$test_dir/<sandbox>}}"
print -r -- "  state:  decoy_unchanged=$([[ $decoy_after == "$decoy_snapshot" ]] && echo yes || echo no)"

# Case 2: Fallback to brew --prefix when prefix contains spaces and glob characters.
: >| "$STUB_LOG"
out2=$(
  export HOME="$empty_home"
  unset AUTOJUMP_BREW_MARKER found file autojump_paths
  path=($test_dir/bin)
  source "$plugin" >| "$test_dir/c2_stdout" 2>| "$test_dir/c2_stderr"
  st=$?
  print -r -- "st=$st|brew=${AUTOJUMP_BREW_MARKER:-__UNSET__}|leaked=${+autojump_paths},${+file},${+found}"
)
c2_stdout=$(<"$test_dir/c2_stdout")
c2_stderr=$(<"$test_dir/c2_stderr")
c2_args=$(<"$STUB_LOG")
(( tests++ ))
if [[ $out2 == "st=0|brew=${expected_brew_script}|leaked=0,0,0" \
   && -z $c2_stdout && -z $c2_stderr \
   && $c2_args == $'argc=1\narg=--prefix' ]]; then
  print -r -- 'PASS: [success] brew --prefix fallback handles prefix with spaces and passes single --prefix arg'
else
  print -r -- 'FAIL: [success] brew --prefix fallback handles prefix with spaces and passes single --prefix arg'
  (( failures++ ))
fi
print -r -- "  result: ${${out2//$test_dir/<sandbox>}}"
print -r -- "  args:   ${(j: | :)${(f)c2_args}}"
print -r -- "  stdout: ${(qqq)c2_stdout} stderr: ${(qqq)${c2_stderr//$test_dir/<sandbox>}}"

# Case 3: With sh_word_split and glob_subst enabled, quoted array and paths prevent word-splitting and glob expansion.
: >| "$STUB_LOG"
out3=$(
  setopt sh_word_split glob_subst
  export HOME="$spaced_home"
  unset AUTOJUMP_MARKER AUTOJUMP_DECOY found file autojump_paths
  path=($test_dir/empty_bin)
  source "$plugin" >| "$test_dir/c3_stdout" 2>| "$test_dir/c3_stderr"
  st=$?
  print -r -- "st=$st|marker=${AUTOJUMP_MARKER:-__UNSET__}|decoy=${+AUTOJUMP_DECOY}|leaked=${+autojump_paths},${+file},${+found}"
)
c3_stdout=$(<"$test_dir/c3_stdout")
c3_stderr=$(<"$test_dir/c3_stderr")
decoy_after=$(<"$decoy_script")
(( tests++ ))
if [[ $out3 == "st=0|marker=${expected_home_script}|decoy=0|leaked=0,0,0" \
   && -z $c3_stdout && -z $c3_stderr && $decoy_after == "$decoy_snapshot" ]]; then
  print -r -- 'PASS: [edge] quoted paths survive sh_word_split and glob_subst without expanding into decoy'
else
  print -r -- 'FAIL: [edge] quoted paths survive sh_word_split and glob_subst without expanding into decoy'
  (( failures++ ))
fi
print -r -- "  result: ${${out3//$test_dir/<sandbox>}}"
print -r -- "  stdout: ${(qqq)c3_stdout} stderr: ${(qqq)${c3_stderr//$test_dir/<sandbox>}}"
print -r -- "  state:  decoy_unchanged=$([[ $decoy_after == "$decoy_snapshot" ]] && echo yes || echo no)"

# Case 4: Pre-existing found=1 in environment does not suppress the missing-autojump notice.
: >| "$STUB_LOG"
out4=$(
  export HOME="$empty_home"
  found=1
  unset AUTOJUMP_MARKER AUTOJUMP_BREW_MARKER
  path=($test_dir/empty_bin)
  source "$plugin" >| "$test_dir/c4_stdout" 2>| "$test_dir/c4_stderr"
  st=$?
  print -r -- "st=$st|leaked=${+autojump_paths},${+file},${+found}"
)
c4_stdout=$(<"$test_dir/c4_stdout")
c4_stderr=$(<"$test_dir/c4_stderr")
(( tests++ ))
if [[ $out4 == 'st=0|leaked=0,0,0' \
   && $c4_stdout == '[oh-my-zsh] autojump not found. Please install it first.' \
   && -z $c4_stderr ]]; then
  print -r -- 'PASS: [edge] pre-existing found=1 still initializes found=0 and reports missing autojump'
else
  print -r -- 'FAIL: [edge] pre-existing found=1 still initializes found=0 and reports missing autojump'
  (( failures++ ))
fi
print -r -- "  result: $out4"
print -r -- "  stdout: ${(qqq)c4_stdout} stderr: ${(qqq)c4_stderr}"

# Case 5: Nothing installed and no brew prints install message, exits 0, and leaks no variables.
: >| "$STUB_LOG"
out5=$(
  export HOME="$empty_home"
  unset found file autojump_paths AUTOJUMP_MARKER AUTOJUMP_BREW_MARKER
  path=($test_dir/empty_bin)
  source "$plugin" >| "$test_dir/c5_stdout" 2>| "$test_dir/c5_stderr"
  st=$?
  print -r -- "st=$st|leaked=${+autojump_paths},${+file},${+found}"
)
c5_stdout=$(<"$test_dir/c5_stdout")
c5_stderr=$(<"$test_dir/c5_stderr")
(( tests++ ))
if [[ $out5 == 'st=0|leaked=0,0,0' \
   && $c5_stdout == '[oh-my-zsh] autojump not found. Please install it first.' \
   && -z $c5_stderr ]]; then
  print -r -- 'PASS: [edge] missing autojump and brew prints install notice, exits 0, and cleans up locals'
else
  print -r -- 'FAIL: [edge] missing autojump and brew prints install notice, exits 0, and cleans up locals'
  (( failures++ ))
fi
print -r -- "  result: $out5"
print -r -- "  stdout: ${(qqq)c5_stdout} stderr: ${(qqq)c5_stderr}"

print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
