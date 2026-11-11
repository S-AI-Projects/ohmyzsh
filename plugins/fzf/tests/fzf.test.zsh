#!/usr/bin/env zsh
# Fixture test for the fzf plugin. Runs in a private sandbox without touching host fzf installs.
# Usage: zsh -f plugins/fzf/tests/fzf.test.zsh [path/to/fzf.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/fzf.plugin.zsh}
test_dir=$(mktemp -d "${${TMPDIR:-/tmp}%/}/fzf-test.XXXXXX") || exit 1
test_dir=${test_dir:A}
orig_path=($path)
trap 'path=($orig_path); command rm -rf -- "$test_dir"' EXIT

export HOME=$test_dir/home ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export STUB_LOG=$test_dir/args.log

REAL_CAT=${commands[cat]}
if [[ -z $REAL_CAT ]]; then
  print -u2 -r -- 'FAIL: missing required system utility (cat)'
  exit 1
fi

empty_base=$test_dir/empty_base
good_base=$test_dir/good_base
command mkdir -p -- \
  "$HOME" "$ZDOTDIR" "$ZSH_CACHE_DIR" \
  "$test_dir/nocmd_bin" "$test_dir/fzf_047_bin" "$test_dir/fzf_056_bin" \
  "$empty_base" "$good_base/shell"

# fzf_setup_error runs `cat >&2 <<'EOF'`, so symlink cat into the stub directories.
command ln -s -- "$REAL_CAT" "$test_dir/nocmd_bin/cat"
command ln -s -- "$REAL_CAT" "$test_dir/fzf_047_bin/cat"
command ln -s -- "$REAL_CAT" "$test_dir/fzf_056_bin/cat"

print -r -- 'FZF_MARKER=loaded_from_base' >| "$good_base/shell/key-bindings.zsh"

# Stub fzf 0.47.0 (below 0.48.0 threshold for fzf --zsh)
command cat >| "$test_dir/fzf_047_bin/fzf" <<'STUB'
#!/bin/sh
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
if [ "$1" = "--version" ]; then
  printf '%s\n' '0.47.0 (brew)'
  exit 0
fi
exit 2
STUB

# Stub fzf 0.56.3 (supports fzf --zsh)
command cat >| "$test_dir/fzf_056_bin/fzf" <<'STUB'
#!/bin/sh
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
if [ "$1" = "--version" ]; then
  printf '%s\n' '0.56.3 (brew)'
  exit 0
fi
if [ "$1" = "--zsh" ]; then
  printf '%s\n' 'FZF_ZSH_MARKER=loaded_via_zsh_flag'
  exit 0
fi
exit 2
STUB

command chmod 0755 "$test_dir/fzf_047_bin/fzf" "$test_dir/fzf_056_bin/fzf" || exit 1

typeset -i tests=0 failures=0

# Case 1 (edge): empty FZF_BASE triggers Cannot find error on stderr, leaves marker unset, and still mutates PATH.
out1=$(
  export FZF_BASE="$empty_base"
  unset FZF_MARKER FZF_ZSH_MARKER FZF_DEFAULT_COMMAND
  path=($test_dir/nocmd_bin)
  path_before=$PATH
  source "$plugin" >| "$test_dir/c1_stdout" 2>| "$test_dir/c1_stderr"
  st=$?
  path_after=$PATH
  print -r -- "st=$st|marker=${FZF_MARKER:-__UNSET__}|path_gained=$([[ $path_after == "$path_before:$empty_base/bin" ]] && echo yes || echo no)"
)
c1_stdout=$(<"$test_dir/c1_stdout")
c1_stderr=$(<"$test_dir/c1_stderr")
(( tests++ ))
if [[ $out1 == 'st=0|marker=__UNSET__|path_gained=yes' \
   && -z $c1_stdout \
   && $c1_stderr == *'key-bindings.zsh'* \
   && $c1_stderr == *'[oh-my-zsh] fzf plugin: Cannot find fzf installation directory.'* ]]; then
  print -r -- 'PASS: [edge] empty FZF_BASE prints Cannot find diagnostic, leaves marker unset, and records PATH change'
else
  print -r -- 'FAIL: [edge] empty FZF_BASE prints Cannot find diagnostic, leaves marker unset, and records PATH change'
  (( failures++ ))
fi
print -r -- "  state:  $out1"
print -r -- "  stderr: ${(qqq)${c1_stderr//$test_dir/<sandbox>}}"

# Case 2 (edge): calling fzf_setup_using_base_dir directly on empty FZF_BASE returns non-zero (127).
src=$(<"$plugin") || exit 1
out2=$(
  export FZF_BASE="$empty_base"
  unset FZF_MARKER
  path=($test_dir/nocmd_bin)
  eval "${src%%$'\n'fzf_setup_using_fzf \\*}"
  fzf_setup_using_base_dir >| "$test_dir/c2_stdout" 2>| "$test_dir/c2_stderr"
  st=$?
  print -r -- "st=$st|marker=${FZF_MARKER:-__UNSET__}"
)
c2_stderr=$(<"$test_dir/c2_stderr")
(( tests++ ))
if [[ $out2 == 'st=127|marker=__UNSET__' && $c2_stderr == *'key-bindings.zsh'* ]]; then
  print -r -- 'PASS: [edge] fzf_setup_using_base_dir returns non-zero 127 when shell/key-bindings.zsh is absent'
else
  print -r -- 'FAIL: [edge] fzf_setup_using_base_dir returns non-zero 127 when shell/key-bindings.zsh is absent'
  (( failures++ ))
fi
print -r -- "  state:  $out2"
print -r -- "  stderr: ${(qqq)${c2_stderr//$test_dir/<sandbox>}}"

# Case 3 (success): corrected FZF_BASE with shell/key-bindings.zsh loads cleanly with empty stderr.
out3=$(
  export FZF_BASE="$good_base"
  unset FZF_MARKER FZF_DEFAULT_COMMAND
  path=($test_dir/nocmd_bin)
  path_before=$PATH
  source "$plugin" >| "$test_dir/c3_stdout" 2>| "$test_dir/c3_stderr"
  st=$?
  path_after=$PATH
  print -r -- "st=$st|marker=${FZF_MARKER:-__UNSET__}|path_gained=$([[ $path_after == "$path_before:$good_base/bin" ]] && echo yes || echo no)"
)
c3_stdout=$(<"$test_dir/c3_stdout")
c3_stderr=$(<"$test_dir/c3_stderr")
(( tests++ ))
if [[ $out3 == 'st=0|marker=loaded_from_base|path_gained=yes' && -z $c3_stdout && -z $c3_stderr ]]; then
  print -r -- 'PASS: [success] corrected FZF_BASE containing shell/key-bindings.zsh succeeds with empty stderr'
else
  print -r -- 'FAIL: [success] corrected FZF_BASE containing shell/key-bindings.zsh succeeds with empty stderr'
  (( failures++ ))
fi
print -r -- "  state:  $out3"
print -r -- "  stderr: ${(qqq)c3_stderr}"

# Case 4 (edge): fzf_setup_using_fzf rejects fzf 0.47.0 (< 0.48.0) with status 1 and never invokes --zsh.
: >| "$STUB_LOG"
out4=$(
  export FZF_BASE="$empty_base"
  unset FZF_ZSH_MARKER
  path=($test_dir/fzf_047_bin)
  eval "${src%%$'\n'fzf_setup_using_fzf \\*}"
  fzf_setup_using_fzf >| "$test_dir/c4_stdout" 2>| "$test_dir/c4_stderr"
  st=$?
  print -r -- "st=$st|zsh_marker=${FZF_ZSH_MARKER:-__UNSET__}"
)
c4_args=$(<"$STUB_LOG")
c4_stderr=$(<"$test_dir/c4_stderr")
(( tests++ ))
if [[ $out4 == 'st=1|zsh_marker=__UNSET__' \
   && -z $c4_stderr \
   && $c4_args == $'argc=1\narg=--version' ]]; then
  print -r -- 'PASS: [edge] fzf_setup_using_fzf returns 1 for fzf 0.47.0 without calling fzf --zsh'
else
  print -r -- 'FAIL: [edge] fzf_setup_using_fzf returns 1 for fzf 0.47.0 without calling fzf --zsh'
  (( failures++ ))
fi
print -r -- "  state:  $out4"
print -r -- "  args:   ${(j: | :)${(f)c4_args}}"

# Case 5 (success): fzf 0.56.3 succeeds via fzf_setup_using_fzf without needing FZF_BASE.
: >| "$STUB_LOG"
out5=$(
  export FZF_BASE="$empty_base"
  unset FZF_ZSH_MARKER FZF_MARKER FZF_DEFAULT_COMMAND
  path=($test_dir/fzf_056_bin)
  source "$plugin" >| "$test_dir/c5_stdout" 2>| "$test_dir/c5_stderr"
  st=$?
  print -r -- "st=$st|zsh_marker=${FZF_ZSH_MARKER:-__UNSET__}|base_marker=${FZF_MARKER:-__UNSET__}"
)
c5_args=$(<"$STUB_LOG")
c5_stdout=$(<"$test_dir/c5_stdout")
c5_stderr=$(<"$test_dir/c5_stderr")
(( tests++ ))
if [[ $out5 == 'st=0|zsh_marker=loaded_via_zsh_flag|base_marker=__UNSET__' \
   && -z $c5_stdout && -z $c5_stderr \
   && $c5_args == $'argc=1\narg=--version\nargc=1\narg=--zsh' ]]; then
  print -r -- 'PASS: [success] fzf 0.56.3 initializes via fzf --zsh cleanly even with empty FZF_BASE'
else
  print -r -- 'FAIL: [success] fzf 0.56.3 initializes via fzf --zsh cleanly even with empty FZF_BASE'
  (( failures++ ))
fi
print -r -- "  state:  $out5"
print -r -- "  args:   ${(j: | :)${(f)c5_args}}"

print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
