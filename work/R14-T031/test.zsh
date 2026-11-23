plugin=$ZSH/plugins/ufw
T=$(mktemp -d "$TMPDIR/ufw.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p $T/bin
log=$T/argv.log

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [$2]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

fpath=($plugin $fpath)
autoload -Uz compinit
compinit -u -d $T/zcompdump
eq "success: completion bound to ufw" "${_comps[ufw]}" "_ufw"

readme=$(<$plugin/README.md)
body=$(<$plugin/_ufw)
for c in ${(f)"$(print -rl -- ${(M)${(f)readme}:#\* \`*} | sed -E 's/^\* `([a-z]+).*/\1/')"}; do
  [[ $body == *"'$c:"* ]]
  eq "success: README command '$c' is completed" $? 0
done

eval "$(sed -n '/^function _ufw_delete_rules/,/^}/p' $plugin/_ufw)"

print -r -- '#!/bin/sh
echo "$@" >> '$log'
exit 1' > $T/bin/ufw
chmod +x $T/bin/ufw
PATH=$T/bin:$PATH
out=$(_ufw_delete_rules); rc=$?
eq "edge: inactive firewall prints no rules" "$out" ""
eq "edge: inactive firewall exit status" $rc 0
eq "edge: inactive firewall probed once with status only" "$(<$log)" "status"

: > $log
print -r -- '#!/bin/sh
echo "$@" >> '$log'
case "$*" in
  "status numbered") printf "Status: active\n\n     To                         Action      From\n     --                         ------      ----\n[ 1] 22/tcp                     ALLOW IN    Anywhere\n" ;;
esac
exit 0' > $T/bin/ufw
out=$(_ufw_delete_rules); rc=$?
eq "success: active firewall lists numbered rule" "$out" '"1[22/tcp                     ALLOW IN    Anywhere]" '
eq "success: active firewall exit status" $rc 0
eq "success: ufw argv" "${(j:|:)${(f)$(<$log)}}" "status|status numbered"
