#!/usr/bin/env zsh

setopt errexit nounset

case "$ZTODOXIDE_CASE" in
  success)
    # This mirrors the documented setup command. The stub records its argv.
    zoxide add "$ZOXIDE_TEST_TARGET"
    setup_status=$?

    source "$ZSH/plugins/zoxide/zoxide.plugin.zsh"
    bootstrap_status=$?

    before_pwd=$PWD
    z 'my project' > "$ZOXIDE_TEST_OUTPUT"
    command_status=$?
    command_output=$(<"$ZOXIDE_TEST_OUTPUT")
    after_pwd=$PWD

    print -r -- "setup_status=$setup_status"
    print -r -- "bootstrap_status=$bootstrap_status"
    print -r -- "command_output=$command_output"
    print -r -- "command_status=$command_status"
    print -r -- "before_pwd=$before_pwd"
    print -r -- "after_pwd=$after_pwd"

    [[ $setup_status -eq 0 ]]
    [[ $bootstrap_status -eq 0 ]]
    [[ $command_status -eq 0 ]]
    [[ $before_pwd != $ZOXIDE_TEST_TARGET ]]
    [[ $after_pwd == $ZOXIDE_TEST_TARGET ]]
    [[ $command_output == $ZOXIDE_TEST_TARGET ]]
    ;;
  missing-command)
    before_pwd=$PWD
    source "$ZSH/plugins/zoxide/zoxide.plugin.zsh"
    bootstrap_status=$?
    after_pwd=$PWD

    print -r -- "bootstrap_status=$bootstrap_status"
    print -r -- "function_z=$(( $+functions[z] ))"
    print -r -- "before_pwd=$before_pwd"
    print -r -- "after_pwd=$after_pwd"

    [[ $bootstrap_status -eq 0 ]]
    [[ $+functions[z] -eq 0 ]]
    [[ $after_pwd == $before_pwd ]]
    ;;
  *)
    print -u2 -r -- "Unknown test case: $ZTODOXIDE_CASE"
    exit 2
    ;;
esac
