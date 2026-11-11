#!/usr/bin/env zsh
# Fixture test for the cp plugin. Runs in a private sandbox and never calls real rsync.
# Usage: zsh -f plugins/cp/tests/cp.test.zsh [path/to/cp.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/cp.plugin.zsh}
test_dir=$(mktemp -d "${${TMPDIR:-/tmp}%/}/cp-test.XXXXXX") || exit 1
orig_path=($path)
orig_pwd=$PWD
trap 'cd "$orig_pwd" 2>/dev/null || true; path=($orig_path); command rm -rf -- "$test_dir"' EXIT

export HOME=$test_dir/home ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export STUB_LOG=$test_dir/args.log STUB_STATUS_FILE=$test_dir/stub_status
work_dir=$test_dir/work
command mkdir -p -- "$HOME" "$ZDOTDIR" "$ZSH_CACHE_DIR" "$test_dir/bin" "$test_dir/empty_bin" "$work_dir/dir with space" "$work_dir/dest"
print -r -- 'sample payload' >| "$work_dir/src.txt"
src_snapshot=$(<"$work_dir/src.txt")
backup_path="/tmp/rsync-${USERNAME}"
if [[ -e $backup_path ]]; then
  backup_before=present
else
  backup_before=absent
fi

# compinit must be loaded before sourcing plugins/cp because cp.plugin.zsh invokes compdef.
autoload -Uz compinit && compinit -D || exit 1

command cat >| "$test_dir/bin/rsync" <<'STUB'
#!/bin/sh
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
status=0
if [ -r "$STUB_STATUS_FILE" ]; then
  read -r status < "$STUB_STATUS_FILE"
fi
exit "$status"
STUB
command chmod 0755 "$test_dir/bin/rsync" || exit 1
path=($test_dir/bin)

source "$plugin" >| "$test_dir/source_stdout" 2>| "$test_dir/source_stderr"
source_status=$?

typeset -i tests=0 failures=0

# Case 1: completion entry point registered after compinit
(( tests++ ))
actual_comp=${_comps[cpv]:-__UNSET__}
if [[ $source_status == 0 && $actual_comp == _files && -z $(<"$test_dir/source_stderr") ]]; then
  print -r -- 'PASS: [success] compdef registers _files completion for cpv'
else
  print -r -- 'FAIL: [success] compdef registers _files completion for cpv'
  (( failures++ ))
fi
print -r -- "  status: $source_status (expected 0)"
print -r -- "  comp:   ${(qqq)actual_comp} (expected \"_files\")"
print -r -- "  args:   (none)"
print -r -- "  state:  source_stderr=${(qqq)$(<"$test_dir/source_stderr")}"

check_cpv() {
  # check_cpv <success|edge> <description> <use_stub:1|0> <stub_exit> <expected_status> <expected_args> <cmd>
  local kind=$1 description=$2 use_stub=$3 stub_exit=$4 expected_status=$5 expected_args=$6 cmd=$7
  local actual_status actual_stdout actual_stderr actual_args src_after backup_after

  print -r -- "$stub_exit" >| "$STUB_STATUS_FILE"
  : >| "$STUB_LOG"
  if [[ $use_stub == 1 ]]; then
    path=($test_dir/bin)
  else
    path=($test_dir/empty_bin)
  fi

  eval "$cmd" >| "$test_dir/stdout" 2>| "$test_dir/stderr"
  actual_status=$?
  actual_stdout=$(<"$test_dir/stdout")
  actual_stderr=$(<"$test_dir/stderr")
  actual_args=$(<"$STUB_LOG")
  src_after=$(<"$work_dir/src.txt")
  if [[ -e $backup_path ]]; then
    backup_after=present
  else
    backup_after=absent
  fi

  (( tests++ ))
  if [[ $actual_status == $expected_status \
     && $actual_args == "$expected_args" \
     && $src_after == "$src_snapshot" \
     && $backup_before == "$backup_after" ]]; then
    if [[ $use_stub == 1 && -n $actual_stderr ]]; then
      print -r -- "FAIL: [$kind] $description"
      (( failures++ ))
    elif [[ $use_stub == 0 && $actual_stderr != *"command not found"* ]]; then
      print -r -- "FAIL: [$kind] $description"
      (( failures++ ))
    else
      print -r -- "PASS: [$kind] $description"
    fi
  else
    print -r -- "FAIL: [$kind] $description"
    (( failures++ ))
  fi
  print -r -- "  status: $actual_status (expected $expected_status)"
  print -r -- "  stdout: ${(qqq)actual_stdout}"
  print -r -- "  stderr: ${(qqq)actual_stderr}"
  print -r -- "  args:   ${(j: | :)${(f)actual_args}} (expected ${(j: | :)${(f)expected_args}})"
  print -r -- "  state:  src_unchanged=$([[ $src_after == "$src_snapshot" ]] && echo yes || echo no) backup_before=$backup_before backup_after=$backup_after"
}

fixed_args=$'arg=-pogbr\narg=-hhh\narg=--backup-dir=/tmp/rsync-'"${USERNAME}"$'\narg=-e\narg=/dev/null\narg=--progress'

cd "$work_dir" || exit 1

check_cpv success \
  'minimum argument list cpv src.txt dest/ forwards 6 fixed options plus 2 paths' \
  1 0 0 \
  $'argc=8\n'"${fixed_args}"$'\narg=src.txt\narg=dest/' \
  'cpv src.txt dest/'

check_cpv success \
  'optional -n flag, spaced path, and literal wildcard arrive as separate arguments' \
  1 0 0 \
  $'argc=10\n'"${fixed_args}"$'\narg=-n\narg=dir with space/\narg=*.txt\narg=dest/' \
  'cpv -n "dir with space/" "*.txt" dest/'

check_cpv edge \
  'documented invalid remote path host:/src preserves -e /dev/null and returns rsync status 12' \
  1 12 12 \
  $'argc=8\n'"${fixed_args}"$'\narg=host:/src\narg=dest/' \
  'cpv host:/src dest/'

check_cpv edge \
  'missing rsync executable exits 127 and leaves files untouched' \
  0 0 127 \
  '' \
  'cpv src.txt dest/'

cd "$orig_pwd" || exit 1
print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
