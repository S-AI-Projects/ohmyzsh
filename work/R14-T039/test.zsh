plugin=$ZSH/plugins/sudo/sudo.plugin.zsh
T=$(mktemp -d "$TMPDIR/sudo.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p $T/bin
PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [$2]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

zle_calls=()
bind_calls=()
zle() { zle_calls+=("$*"); return 1 }
bindkey() { bind_calls+=("$*") }

source $plugin

eq "success: widget registered" "$zle_calls[1]" "-N sudo-command-line"
eq "success: bound in emacs, vicmd and viins" "${(j:|:)bind_calls}" '-M emacs \e\e sudo-command-line|-M vicmd \e\e sudo-command-line|-M viins \e\e sudo-command-line'

press() {
  BUFFER=$1
  LBUFFER=$1
  CURSOR=${#1}
  sudo-command-line
  print -r -- "$LBUFFER$RBUFFER"
}

unset EDITOR VISUAL SUDO_EDITOR
eq "success: prefix is added" "$(press 'apt install build-essential')" "sudo apt install build-essential"
eq "success: prefix is toggled off" "$(press 'sudo apt install build-essential')" "apt install build-essential"
eq "success: -e prefix is toggled off" "$(press 'sudo -e /etc/hosts')" "/etc/hosts"
eq "success: leading space is preserved" "$(press ' ls -l')" " sudo ls -l"

print -s 'systemctl restart nginx'
eq "success: empty buffer reuses the last history entry" "$(press '')" "sudo systemctl restart nginx"

EDITOR=vim
eq "success: editor command becomes sudo -e" "$(press 'vim /etc/hosts')" "sudo -e /etc/hosts"
eq "success: sudo -e goes back to the editor" "$(press 'sudo -e /etc/hosts')" "vim /etc/hosts"
eq "success: non-editor command still gets sudo" "$(press 'ls /root')" "sudo ls /root"
eq "edge: editor with a longer name is not matched" "$(press 'vimdiff a b')" "sudo vimdiff a b"

SUDO_EDITOR=nano
eq "edge: SUDO_EDITOR wins over EDITOR" "$(press 'nano /etc/hosts')" "sudo -e /etc/hosts"
eq "edge: another editor is a plain command" "$(press 'vim /etc/hosts')" "sudo vim /etc/hosts"
unset SUDO_EDITOR

alias v=vim
eq "success: alias to the editor becomes sudo -e" "$(press 'v /etc/hosts')" "sudo -e /etc/hosts"

