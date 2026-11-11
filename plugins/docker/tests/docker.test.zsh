#!/usr/bin/env zsh
# Fixture test for the docker plugin. Runs in a private sandbox with no Docker daemon.
# Usage: zsh -f plugins/docker/tests/docker.test.zsh [path/to/docker.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/docker.plugin.zsh}
test_dir=$(mktemp -d "${${TMPDIR:-/tmp}%/}/docker-test.XXXXXX") || exit 1
orig_path=($path)
trap 'path=($orig_path); command rm -rf -- "$test_dir"' EXIT

export HOME=$test_dir/home ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export DOCKER_HOST='tcp://127.0.0.1:1'
export STUB_LOG=$test_dir/args.log

REAL_MKDIR=${commands[mkdir]}
REAL_CP=${commands[cp]}
REAL_SLEEP=${commands[sleep]}
if [[ -z $REAL_MKDIR || -z $REAL_CP || -z $REAL_SLEEP ]]; then
  print -u2 -r -- 'FAIL: missing required system utility (mkdir, cp, or sleep)'
  exit 1
fi

command mkdir -p -- "$HOME" "$ZDOTDIR" "$ZSH_CACHE_DIR" "$test_dir/bin" "$test_dir/empty_bin"
command ln -s -- "$REAL_MKDIR" "$test_dir/bin/mkdir"
command ln -s -- "$REAL_CP" "$test_dir/bin/cp"
command ln -s -- "$REAL_SLEEP" "$test_dir/bin/sleep"

# Stub docker: logs argc/args for non-completion calls, answers --version 24.0.2 and completion zsh.
command cat >| "$test_dir/bin/docker" <<'STUB'
#!/bin/sh
if [ "$1" = "--version" ]; then
  printf '%s\n' 'Docker version 24.0.2, build cb74dfcd85'
  exit 0
fi
if [ "$1" = "completion" ] && [ "$2" = "zsh" ]; then
  printf '%s\n' '#compdef docker (stub completion 24.0.2)'
  exit 0
fi
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
exit 0
STUB
command chmod 0755 "$test_dir/bin/docker" || exit 1

typeset -i tests=0 failures=0

# Case 1 (edge): sourcing with no docker on PATH still defines aliases, leaves cache untouched, and dbl exits 127.
no_docker_out=$(
  export ZSH_CACHE_DIR="$test_dir/cache_nodocker"
  command mkdir -p -- "$ZSH_CACHE_DIR"
  path=($test_dir/empty_bin)
  source "$plugin" 2>| "$test_dir/c1_src_err"
  src_st=$?
  eval 'dbl' >| "$test_dir/c1_out" 2>| "$test_dir/c1_err"
  dbl_st=$?
  cache_entries=( "$ZSH_CACHE_DIR"/*(DN) )
  print -r -- "src=$src_st|dbl_st=$dbl_st|dbl=${aliases[dbl]:-}|dcin=${aliases[dcin]:-}|dcls=${aliases[dcls]:-}|cache_count=${#cache_entries}"
)
c1_err=$(<"$test_dir/c1_err")
c1_src_err=$(<"$test_dir/c1_src_err")
(( tests++ ))
if [[ $no_docker_out == 'src=0|dbl_st=127|dbl=docker build|dcin=docker container inspect|dcls=docker container ls|cache_count=0' \
   && -z $c1_src_err && $c1_err == *'command not found: docker'* ]]; then
  print -r -- 'PASS: [edge] missing docker defines aliases, leaves cache untouched, and dbl exits 127'
else
  print -r -- 'FAIL: [edge] missing docker defines aliases, leaves cache untouched, and dbl exits 127'
  (( failures++ ))
fi
print -r -- "  state:  $no_docker_out"
print -r -- "  stderr: ${(qqq)c1_err}"

# Load plugin in main shell with stubbed docker on PATH and unusable DOCKER_HOST (daemon independent).
path=($test_dir/bin)
source "$plugin" 2>| "$test_dir/src_stderr"
src_status=$?

# Wait for background completion job (&|) to finish writing $ZSH_CACHE_DIR/completions/_docker.
typeset -i tries=0
while [[ ! -s "$ZSH_CACHE_DIR/completions/_docker" && $tries -lt 50 ]]; do
  "$REAL_SLEEP" 0.1
  (( tries++ ))
done

src_stderr=$(<"$test_dir/src_stderr")
comp_content=''
[[ -f "$ZSH_CACHE_DIR/completions/_docker" ]] && comp_content=$(<"$ZSH_CACHE_DIR/completions/_docker")

# Case 2 (success): autoloaded is-at-least enables docker completion zsh (>23.0.0) without stderr errors.
(( tests++ ))
if [[ $src_status == 0 && -z $src_stderr && $comp_content == '#compdef docker (stub completion 24.0.2)' ]]; then
  print -r -- 'PASS: [success] docker 24.0.2 completion cache is generated cleanly via docker completion zsh'
else
  print -r -- 'FAIL: [success] docker 24.0.2 completion cache is generated cleanly via docker completion zsh'
  (( failures++ ))
fi
print -r -- "  status: $src_status (expected 0)"
print -r -- "  stderr: ${(qqq)src_stderr}"
print -r -- "  cache:  ${(qqq)${comp_content%%$'\n'*}}"

# Case 3 (success): dbl, dcin, and dcls forward exact quoted arguments without contacting a daemon.
: >| "$STUB_LOG"
eval 'dbl -t "my image:1.0" "ctx dir/" && dcin web && dcls -a' >| "$test_dir/c3_out" 2>| "$test_dir/c3_err"
c3_status=$?
c3_args=$(<"$STUB_LOG")
c3_err=$(<"$test_dir/c3_err")
expected_c3_args=$'argc=4\narg=build\narg=-t\narg=my image:1.0\narg=ctx dir/\nargc=3\narg=container\narg=inspect\narg=web\nargc=3\narg=container\narg=ls\narg=-a'

(( tests++ ))
if [[ $c3_status == 0 && -z $c3_err && $c3_args == "$expected_c3_args" ]]; then
  print -r -- 'PASS: [success] dbl, dcin, and dcls preserve quoted arguments independent of Docker daemon'
else
  print -r -- 'FAIL: [success] dbl, dcin, and dcls preserve quoted arguments independent of Docker daemon'
  (( failures++ ))
fi
print -r -- "  status: $c3_status (expected 0)"
print -r -- "  args:   ${(j: | :)${(f)c3_args}}"
print -r -- "  state:  DOCKER_HOST=$DOCKER_HOST"

print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
