plugin=$ZSH/plugins/nmap/nmap.plugin.zsh
readme=$ZSH/plugins/nmap/README.md
T=$(mktemp -d "$TMPDIR/nmap.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p $T/bin $T/work
log=$T/argv.log

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [$2]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

sed -n '/^\$ nmap_open_ports/,/^\$ echo/p' $readme | sed '1d;$d' > $T/documented.out
documented_cmd=$(sed -n 's/^\$ \(nmap_open_ports .*\)/\1/p' $readme)

print -r -- '#!/bin/sh
printf "%s|" "$@" >> '$log'
echo >> '$log'
if [ "$1" = "--open" ] && [ -z "$2" ]; then
  echo "WARNING: No targets were specified, so 0 hosts scanned." >&2
  exit 1
fi
cat '$T'/documented.out' > $T/bin/nmap
print -r -- '#!/bin/sh
printf "sudo|" >> '$log'
exec "$@"' > $T/bin/sudo
chmod +x $T/bin/nmap $T/bin/sudo
PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin
rehash

source $plugin
cd $T/work
touch keep.txt
before="$(print -r -- *)"

eq "success: README documents the command" "$documented_cmd" "nmap_open_ports 192.0.2.10"
eq "success: alias expansion" "$aliases[nmap_open_ports]" "nmap --open"

out=$(eval $documented_cmd); rc=$?
eq "success: documented output is what the command prints" "$out" "$(<$T/documented.out)"
eq "success: documented exit status" $rc 0
eq "success: nmap argv" "$(<$log)" "--open|192.0.2.10|"
eq "success: working directory state unchanged" "$(print -r -- *)" "$before"

: > $log
msg=$(eval nmap_open_ports 2>&1); rc=$?
eq "edge: no target fails" $rc 1
eq "edge: no target diagnostic" "$msg" "WARNING: No targets were specified, so 0 hosts scanned."
eq "edge: no target argv is only the alias flag" "$(<$log)" "--open|"

: > $log
eval 'nmap_slow 192.0.2.10' >/dev/null
eq "success: nmap_slow goes through sudo" "$(<$log)" "sudo|-sS|-v|-T1|192.0.2.10|"

: > $log
eval 'nmap_list_interfaces' >/dev/null
eq "success: nmap_list_interfaces argv" "$(<$log)" "--iflist|"
