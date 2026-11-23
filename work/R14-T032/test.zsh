plugin=$ZSH/plugins/fzf/fzf.plugin.zsh
T=$(mktemp -d "$TMPDIR/fzf.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
log=$T/argv.log
mkdir -p $T/bin

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [$2]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

eval "$(sed '/^fzf_setup_using_fzf \\$/,$d' $plugin)"

reset() {
  rm -rf $T/bin $T/com.termux $T/base; mkdir -p $T/bin
  PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin
  unset KB COMP FZF_LOADED FZF_BASE DISABLE_FZF_KEY_BINDINGS PREFIX
  : > $log
  rehash
}

fake_fzf() {
  print -r -- '#!/bin/sh
echo "$@" >> '$log'
case "$1" in
  --version) echo "'$1' (abc1234)" ;;
  --zsh) echo "FZF_LOADED=1" ;;
esac' > $T/bin/fzf
  chmod +x $T/bin/fzf
  rehash
}

reset
fake_fzf 0.60.0
fzf_setup_using_fzf; rc=$?
eq "success: fzf >= 0.48 exit status" $rc 0
eq "success: fzf --zsh output evaluated" "$FZF_LOADED" 1
eq "success: fzf argv, one call per line" "${(j:|:)${(f)$(<$log)}}" "--version|--zsh"

reset
fake_fzf 0.47.0
fzf_setup_using_fzf; rc=$?
eq "edge: fzf below 0.48 rejected" $rc 1
eq "edge: old fzf never asked for --zsh" "$(<$log)" "--version"
eq "edge: old fzf leaves shell untouched" "${FZF_LOADED-unset}" unset

reset
fzf_setup_using_fzf; rc=$?
eq "edge: no fzf on PATH" $rc 1

reset
print -r -- '#!/bin/sh' > $T/bin/apt; chmod +x $T/bin/apt; rehash
export PREFIX=$T/com.termux/usr
fzf_setup_using_debian; rc=$?
eq "edge: termux without fzf installed" $rc 1
mkdir -p $PREFIX/bin $PREFIX/share/fzf
: > $PREFIX/bin/fzf
print 'COMP=1' > $PREFIX/share/fzf/completion.zsh
print 'KB=1' > $PREFIX/share/fzf/key-bindings.zsh
fzf_setup_using_debian; rc=$?
eq "success: termux package exit status" $rc 0
eq "success: termux key bindings sourced" "$KB" 1
eq "success: completion skipped in non-interactive shell" "${COMP-unset}" unset
unset KB
DISABLE_FZF_KEY_BINDINGS=true fzf_setup_using_debian; rc=$?
eq "edge: key bindings disabled still succeeds" $rc 0
eq "edge: key bindings disabled not sourced" "${KB-unset}" unset

reset
export PREFIX=$T/missing
fzf_setup_using_debian; rc=$?
eq "edge: no apt on PATH" $rc 1

reset
mkdir -p $T/base/shell
print 'KB=1' > $T/base/shell/key-bindings.zsh
FZF_BASE=$T/base fzf_setup_using_base_dir; rc=$?
eq "success: FZF_BASE exit status" $rc 0
eq "success: FZF_BASE key bindings sourced" "$KB" 1
eq "success: FZF_BASE bin appended to PATH" "${${PATH##*:}#$T/}" "base/bin"
