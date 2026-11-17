#!/usr/bin/env zsh

setopt aliases

source "$ZSH/plugins/brew/brew.plugin.zsh"

before_pwd=$PWD

# Exercise the actual bci alias with the cask argument omitted.
eval 'bci' > "$BREW_TEST_FAILURE_OUT" 2> "$BREW_TEST_FAILURE_ERR"
failure_status=$?
failure_stdout=$(<"$BREW_TEST_FAILURE_OUT")
failure_stderr=$(<"$BREW_TEST_FAILURE_ERR")
after_failure_pwd=$PWD

# Supplying the cask token is the documented correction.
eval 'bci firefox' > "$BREW_TEST_SUCCESS_OUT" 2> "$BREW_TEST_SUCCESS_ERR"
success_status=$?
success_stdout=$(<"$BREW_TEST_SUCCESS_OUT")
success_stderr=$(<"$BREW_TEST_SUCCESS_ERR")
after_success_pwd=$PWD

print -r -- "failure_status=$failure_status"
print -r -- "failure_stdout=$failure_stdout"
print -r -- "failure_stderr=$failure_stderr"
print -r -- "success_status=$success_status"
print -r -- "success_stdout=$success_stdout"
print -r -- "success_stderr=$success_stderr"
print -r -- "before_pwd=$before_pwd"
print -r -- "after_failure_pwd=$after_failure_pwd"
print -r -- "after_success_pwd=$after_success_pwd"

[[ $failure_status -eq 2 ]] || exit 10
[[ $failure_stderr == 'Error: no cask name was provided (use: bci <cask>)' ]] || exit 11
[[ $success_status -eq 0 ]] || exit 12
[[ $success_stdout == 'firefox: 130.0' ]] || exit 13
[[ -z $failure_stdout && -z $success_stderr ]] || exit 14
[[ $before_pwd == $after_failure_pwd && $before_pwd == $after_success_pwd ]] || exit 15
