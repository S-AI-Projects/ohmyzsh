#!/usr/bin/env zsh

typeset -gA compstate
typeset -ga words described_opts
typeset -gi describe_calls=0 file_calls=0

compdef() { :; }

_describe() {
  describe_calls=$((describe_calls + 1))
  described_opts=()
  for candidate in "${opts[@]}"; do
    [[ -n $candidate ]] && described_opts+=("$candidate")
  done
  compstate[nmatches]=${#described_opts[@]}
  return 0
}

_files() {
  file_calls=$((file_calls + 1))
  return "$JFROG_FILES_STATUS"
}

source "$ZSH/plugins/jfrog/jfrog.plugin.zsh"

words=(jfrog test-word)
CURRENT=2
before_pwd=$PWD
before_path=$PATH

case "$JFROG_TEST_CASE" in
  success)
    _jfrog 2> "$JFROG_TEST_STDERR"
    completion_status=$?
    completion_stderr=$(<"$JFROG_TEST_STDERR")
    after_pwd=$PWD
    after_path=$PATH

    print -r -- "case=success"
    print -r -- "completion_status=$completion_status"
    print -r -- "describe_calls=$describe_calls"
    print -r -- "candidate_count=${#described_opts[@]}"
    for candidate in "${described_opts[@]}"; do
      print -r -- "candidate=$candidate"
    done
    print -r -- "file_calls=$file_calls"
    print -r -- "completion_stderr=$completion_stderr"
    print -r -- "before_pwd=$before_pwd"
    print -r -- "after_pwd=$after_pwd"
    print -r -- "before_path=$before_path"
    print -r -- "after_path=$after_path"

    [[ $completion_status -eq 0 ]] || exit 21
    [[ ${#described_opts[@]} -eq 2 ]] || exit 22
    [[ ${described_opts[1]} == repo-one && ${described_opts[2]} == 'repo two' ]] || exit 23
    [[ $file_calls -eq 0 ]] || exit 24
    [[ -z $completion_stderr ]] || exit 25
    [[ $before_pwd == $after_pwd && $before_path == $after_path ]] || exit 26
    ;;
  cli-failure)
    JFROG_FILES_STATUS=23
    _jfrog 2> "$JFROG_TEST_STDERR"
    completion_status=$?
    completion_stderr=$(<"$JFROG_TEST_STDERR")
    after_pwd=$PWD
    after_path=$PATH

    print -r -- "case=cli-failure"
    print -r -- "completion_status=$completion_status"
    print -r -- "describe_calls=$describe_calls"
    print -r -- "candidate_count=${#described_opts[@]}"
    print -r -- "file_calls=$file_calls"
    print -r -- "completion_stderr=$completion_stderr"
    print -r -- "before_pwd=$before_pwd"
    print -r -- "after_pwd=$after_pwd"
    print -r -- "before_path=$before_path"
    print -r -- "after_path=$after_path"

    [[ $completion_status -eq 23 ]] || exit 31
    [[ ${#described_opts[@]} -eq 0 ]] || exit 32
    [[ $file_calls -eq 1 ]] || exit 33
    [[ $completion_stderr == 'simulated JFrog CLI failure' ]] || exit 34
    [[ $before_pwd == $after_pwd && $before_path == $after_path ]] || exit 35
    ;;
  *)
    print -u2 -r -- "Unknown test case: $JFROG_TEST_CASE"
    exit 2
    ;;
esac
