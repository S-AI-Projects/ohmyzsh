#!/usr/bin/env zsh
# Fixture test for the git plugin. Isolates HOME, git config, PWD, and git binary via stubs.
# Usage: zsh -f plugins/git/tests/git.test.zsh [path/to/git.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/git.plugin.zsh}
zsh_root=${ZSH:-${0:A:h:h:h:h}}
test_dir=$(mktemp -d "${${TMPDIR:-/tmp}%/}/git-test.XXXXXX") || exit 1
test_dir=${test_dir:A}
orig_path=($path)
orig_pwd=$PWD
trap 'cd "$orig_pwd" 2>/dev/null || true; path=($orig_path); command rm -rf -- "$test_dir"' EXIT

export HOME=$test_dir/home ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export GIT_CONFIG_GLOBAL=$test_dir/gitconfig GIT_CONFIG_NOSYSTEM=1
export STUB_LOG=$test_dir/args.log
export STUB_GIT_VERSION_FILE=$test_dir/git_version
export STUB_REVPARSE_STATUS_FILE=$test_dir/revparse_status
export STUB_REPO_ROOT=$test_dir/repo

command mkdir -p -- "$HOME" "$ZDOTDIR" "$ZSH_CACHE_DIR" "$test_dir/bin" "$test_dir/empty_bin" "$test_dir/repo/sub/deep" "$test_dir/outside"
: >| "$GIT_CONFIG_GLOBAL"
print -r -- '2.45.1' >| "$STUB_GIT_VERSION_FILE"
print -r -- '0' >| "$STUB_REVPARSE_STATUS_FILE"

command cat >| "$test_dir/bin/git" <<'STUB'
#!/bin/sh
if [ "$1" = "version" ]; then
  ver="2.45.1"
  if [ -r "$STUB_GIT_VERSION_FILE" ]; then
    read -r ver < "$STUB_GIT_VERSION_FILE"
  fi
  printf 'git version %s\n' "$ver"
  exit 0
fi
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
if [ "$1" = "rev-parse" ] && [ "$2" = "--show-toplevel" ]; then
  st=0
  if [ -r "$STUB_REVPARSE_STATUS_FILE" ]; then
    read -r st < "$STUB_REVPARSE_STATUS_FILE"
  fi
  if [ "$st" -ne 0 ]; then
    exit "$st"
  fi
  printf '%s\n' "$STUB_REPO_ROOT"
  exit 0
fi
if [ "$1" = "symbolic-ref" ]; then
  printf '%s\n' "refs/heads/feature/login"
  exit 0
fi
exit 0
STUB
command chmod 0755 "$test_dir/bin/git" || exit 1

typeset -i tests=0 failures=0

# Run isolated load-time checks in pristine subshells before sourcing git.plugin.zsh in the parent.

# Case 1 (edge): missing git binary on PATH still loads plugin; g returns 127 and grt returns 0 without moving.
c_missing_result=$(
  path=($test_dir/empty_bin)
  autoload -Uz compinit && compinit -D || exit 1
  source "$zsh_root/lib/git.zsh" || exit 1
  source "$plugin" 2>| "$test_dir/c_missing_src_err"
  src_st=$?
  cd "$test_dir/outside" || exit 1
  pwd_b=${PWD:A}
  eval 'g status' >| "$test_dir/c_missing_g_out" 2>| "$test_dir/c_missing_g_err"
  g_st=$?
  eval 'grt' >| "$test_dir/c_missing_grt_out" 2>| "$test_dir/c_missing_grt_err"
  grt_st=$?
  pwd_a=${PWD:A}
  print -r -- "src=$src_st|g=$g_st|grt=$grt_st|same=$([[ $pwd_b == "$pwd_a" ]] && echo yes || echo no)|gfa=${aliases[gfa]}"
)
c_missing_src_err=$(<"$test_dir/c_missing_src_err")
c_missing_g_err=$(<"$test_dir/c_missing_g_err")
(( tests++ ))
if [[ $c_missing_result == 'src=0|g=127|grt=0|same=yes|gfa=git fetch --all --tags --prune --jobs=10' \
   && -z $c_missing_src_err && $c_missing_g_err == *'command not found: git'* ]]; then
  print -r -- 'PASS: [edge] missing git loads cleanly, g exits 127, and grt returns 0 in place'
else
  print -r -- 'FAIL: [edge] missing git loads cleanly, g exits 127, and grt returns 0 in place'
  (( failures++ ))
fi
print -r -- "  state:  $c_missing_result"
print -r -- "  stderr: ${(qqq)c_missing_g_err}"

# Case 2 (edge): git version 2.7.0 omits --jobs=10 on gfa whereas 2.45.1 includes it.
print -r -- '2.7.0' >| "$STUB_GIT_VERSION_FILE"
gfa_old=$(
  path=($test_dir/bin)
  autoload -Uz compinit && compinit -D || exit 1
  source "$zsh_root/lib/git.zsh" || exit 1
  source "$plugin" || exit 1
  print -r -- "${aliases[gfa]}"
)
print -r -- '2.45.1' >| "$STUB_GIT_VERSION_FILE"
gfa_new=$(
  path=($test_dir/bin)
  autoload -Uz compinit && compinit -D || exit 1
  source "$zsh_root/lib/git.zsh" || exit 1
  source "$plugin" || exit 1
  print -r -- "${aliases[gfa]}"
)
(( tests++ ))
if [[ $gfa_old == 'git fetch --all --tags --prune' \
   && $gfa_new == 'git fetch --all --tags --prune --jobs=10' ]]; then
  print -r -- 'PASS: [edge] gfa adapts --jobs=10 based on stubbed git version (2.7.0 vs 2.45.1)'
else
  print -r -- 'FAIL: [edge] gfa adapts --jobs=10 based on stubbed git version (2.7.0 vs 2.45.1)'
  (( failures++ ))
fi
print -r -- "  state:  gfa_2_7_0=${(qqq)gfa_old} gfa_2_45_1=${(qqq)gfa_new}"

# Initialize compinit + lib/git.zsh + git.plugin.zsh in parent for entry-point cases.
autoload -Uz compinit && compinit -D || exit 1
path=($test_dir/bin)
source "$zsh_root/lib/git.zsh" || exit 1
source "$plugin" || exit 1

# Case 3 (success): g forwards arguments including spaced filenames without expansion.
: >| "$STUB_LOG"
cd "$test_dir/repo" || exit 1
eval 'g status -sb "file with space.txt"' >| "$test_dir/c1_out" 2>| "$test_dir/c1_err"
c1_status=$?
c1_args=$(<"$STUB_LOG")
c1_err=$(<"$test_dir/c1_err")
expected_c1=$'argc=3\narg=status\narg=-sb\narg=file with space.txt'
(( tests++ ))
if [[ $c1_status == 0 && -z $c1_err && $c1_args == "$expected_c1" ]]; then
  print -r -- 'PASS: [success] g preserves quoted spaced filenames across stub boundary'
else
  print -r -- 'FAIL: [success] g preserves quoted spaced filenames across stub boundary'
  (( failures++ ))
fi
print -r -- "  status: $c1_status (expected 0)"
print -r -- "  args:   ${(j: | :)${(f)c1_args}}"

# Case 4 (success): grt inside subfolder moves PWD to repository root.
: >| "$STUB_LOG"
print -r -- 0 >| "$STUB_REVPARSE_STATUS_FILE"
cd "$test_dir/repo/sub/deep" || exit 1
pwd_before=${PWD:A}
eval 'grt' >| "$test_dir/c2_out" 2>| "$test_dir/c2_err"
c2_status=$?
pwd_after=${PWD:A}
c2_args=$(<"$STUB_LOG")
c2_err=$(<"$test_dir/c2_err")
(( tests++ ))
if [[ $c2_status == 0 && -z $c2_err \
   && $pwd_before == "$test_dir/repo/sub/deep" \
   && $pwd_after == "$test_dir/repo" \
   && $c2_args == $'argc=2\narg=rev-parse\narg=--show-toplevel' ]]; then
  print -r -- 'PASS: [success] grt changes PWD from subfolder to repository root'
else
  print -r -- 'FAIL: [success] grt changes PWD from subfolder to repository root'
  (( failures++ ))
fi
print -r -- "  status: $c2_status (expected 0)"
print -r -- "  state:  pwd_before=${pwd_before//$test_dir/<sandbox>} pwd_after=${pwd_after//$test_dir/<sandbox>}"
print -r -- "  args:   ${(j: | :)${(f)c2_args}}"

# Case 5 (success): ggpur uses git_current_branch when no branch is given and explicit branch otherwise.
: >| "$STUB_LOG"
eval 'ggpur && ggpur release/1.0' >| "$test_dir/c3_out" 2>| "$test_dir/c3_err"
c3_status=$?
c3_args=$(<"$STUB_LOG")
c3_err=$(<"$test_dir/c3_err")
expected_c3=$'argc=3\narg=symbolic-ref\narg=--quiet\narg=HEAD\nargc=4\narg=pull\narg=--rebase\narg=origin\narg=feature/login\nargc=4\narg=pull\narg=--rebase\narg=origin\narg=release/1.0'
(( tests++ ))
if [[ $c3_status == 0 && -z $c3_err && $c3_args == "$expected_c3" ]]; then
  print -r -- 'PASS: [success] ggpur resolves current branch and accepts explicit branch argument'
else
  print -r -- 'FAIL: [success] ggpur resolves current branch and accepts explicit branch argument'
  (( failures++ ))
fi
print -r -- "  status: $c3_status (expected 0)"
print -r -- "  args:   ${(j: | :)${(f)c3_args}}"

# Case 6 (edge): grt outside a repository (rev-parse exits 128) keeps PWD unchanged and returns 0.
: >| "$STUB_LOG"
print -r -- 128 >| "$STUB_REVPARSE_STATUS_FILE"
cd "$test_dir/outside" || exit 1
pwd_before=${PWD:A}
eval 'grt' >| "$test_dir/c4_out" 2>| "$test_dir/c4_err"
c4_status=$?
pwd_after=${PWD:A}
c4_args=$(<"$STUB_LOG")
c4_err=$(<"$test_dir/c4_err")
(( tests++ ))
if [[ $c4_status == 0 && -z $c4_err \
   && $pwd_before == "$test_dir/outside" && $pwd_after == "$test_dir/outside" \
   && $c4_args == $'argc=2\narg=rev-parse\narg=--show-toplevel' ]]; then
  print -r -- 'PASS: [edge] grt outside a repository stays in PWD and returns 0'
else
  print -r -- 'FAIL: [edge] grt outside a repository stays in PWD and returns 0'
  (( failures++ ))
fi
print -r -- "  status: $c4_status (expected 0)"
print -r -- "  state:  pwd_before=${pwd_before//$test_dir/<sandbox>} pwd_after=${pwd_after//$test_dir/<sandbox>}"
print -r -- "  args:   ${(j: | :)${(f)c4_args}}"

cd "$orig_pwd" || exit 1
print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
