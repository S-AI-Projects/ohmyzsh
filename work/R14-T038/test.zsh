plugin=$ZSH/plugins/eza/eza.plugin.zsh
readme=$ZSH/plugins/eza/README.md
T=$(mktemp -d "$TMPDIR/eza.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p $T/bin $T/empty

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [$2]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

system=/usr/bin:/bin:/usr/sbin:/sbin

(
  PATH=$T/empty:$system
  msg=$(source $plugin 2>&1 >/dev/null); rc=$?
  eq "edge: missing eza makes the plugin return 1" $rc 1
  eq "edge: missing eza diagnostic" "$msg" "zsh eza plugin: eza not found. Please install eza before using this plugin."
  source $plugin 2>/dev/null
  eq "edge: missing eza defines no ls alias" $+aliases[ls] 0
  eq "edge: README explains the same message" "$(grep -c -F 'zsh eza plugin: eza not found. Please install eza before using this plugin.' $readme)" 1
)

print -r -- '#!/bin/sh
exit 0' > $T/bin/eza
chmod +x $T/bin/eza

(
  PATH=$T/bin:$system
  source $plugin; rc=$?
  eq "success: corrected PATH loads the plugin" $rc 0
  eq "success: ls alias" "$aliases[ls]" "eza"
  eq "success: ll alias" "$aliases[ll]" "eza -l"
  eq "success: la alias" "$aliases[la]" "eza -la"
  eq "success: ldot keeps its pattern as one word" "$aliases[ldot]" "eza -ld .*"
  eq "success: lS alias" "$aliases[lS]" "eza -l -ssize"
  eq "success: helpers are cleaned up" "$+functions[_alias_eza]$+functions[_configure_eza]" 00
)

(
  PATH=$T/bin:$system
  zstyle ':omz:plugins:eza' dirs-first yes
  zstyle ':omz:plugins:eza' header yes
  zstyle ':omz:plugins:eza' git-status yes
  source $plugin
  eq "success: header goes in the short flags" "$aliases[ll]" "eza -hl --group-directories-first --git"
  eq "success: plain ls carries the shared flags" "$aliases[ls]" "eza -h --group-directories-first --git"
)

(
  PATH=$T/bin:$system
  zstyle ':omz:plugins:eza' color-scale-mode bogus
  zstyle ':omz:plugins:eza' size-prefix none
  source $plugin
  eq "edge: unsupported color-scale-mode is ignored" "$aliases[ll]" "eza -Bl"
)
