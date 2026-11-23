plugin=$ZSH/plugins/emacs/emacs.plugin.zsh
T=$(mktemp -d "$TMPDIR/emacs.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p $T/bin $T/work
launcher=$ZSH/plugins/emacs/emacsclient.sh

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [${2//$ZSH/<ZSH>}]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

print -r -- '#!/bin/sh
if [ "$1" = --version ]; then echo "emacsclient $(cat '$T'/ver)"; exit 0; fi
if [ "$1" = -a ]; then echo "(t)"; exit 0; fi
printf "%s\n" "$@" > '$T'/last
cat '$T'/out 2>/dev/null
exit 0' > $T/bin/emacsclient
chmod +x $T/bin/emacsclient
PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin
cd $T/work

argv() { print -r -- "${(j:|:)${(f)$(<$T/last)}}" }

print 29.1 > $T/ver
: > $T/out
(
  alias ll='ls -l'
  UNRELATED=keep
  unset EDITOR
  before=$+aliases[emacs]
  source $plugin
  eq "success: emacs alias absent before loading" $before 0
  eq "success: launcher path exported" "$EMACS_PLUGIN_LAUNCHER" "$launcher"
  eq "success: emacs alias" "$aliases[emacs]" "$launcher --no-wait"
  eq "success: e alias" "$aliases[e]" "emacs"
  eq "success: te alias" "$aliases[te]" "$launcher -nw"
  eq "success: eeval alias" "$aliases[eeval]" "$launcher --eval"
  eq "success: EDITOR defaults to launcher" "$EDITOR" "$launcher"
  eq "success: unrelated alias unchanged" "$aliases[ll]" "ls -l"
  eq "success: unrelated variable unchanged" "$UNRELATED" keep

  eval 'te "my file.txt"'
  eq "success: te keeps a spaced filename as one argument" "$(argv)" "--alternate-editor=|-nw|my file.txt"
  eval 'emacs "a b"'
  eq "success: emacs reuses an existing frame" "$(argv)" "--alternate-editor=|--no-wait|a b"
  eval 'emacs'
  eq "success: bare emacs creates a frame" "$(argv)" "--alternate-editor=|--create-frame|--no-wait"
  eval "eeval '(+ 1 2)'"
  eq "success: eeval passes the form untouched" "$(argv)" "--alternate-editor=|--eval|(+ 1 2)"

  print '"/home/me/notes.txt"' > $T/out
  eq "success: efile" "$(efile)" "/home/me/notes.txt"
  eq "success: ecd" "$(ecd)" "/home/me"
  : > $T/out
  msg=$(efile 2>&1); rc=$?
  eq "edge: efile without a buffer fails" $rc 1
  eq "edge: efile explains why" "$msg" "Can't deduce current buffer filename."
  ecd >/dev/null 2>&1
  eq "edge: ecd propagates the failure" $? 1
)

(
  EDITOR=vim
  source $plugin
  eq "edge: preset EDITOR is kept" "$EDITOR" vim
)

print 23.2 > $T/ver
(
  unset EDITOR EMACS_PLUGIN_LAUNCHER
  source $plugin
  eq "edge: emacsclient 23 defines no emacs alias" $+aliases[emacs] 0
  eq "edge: emacsclient 23 leaves EDITOR unset" "${EDITOR-unset}" unset
)
