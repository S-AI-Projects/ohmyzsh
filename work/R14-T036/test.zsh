plugin=$ZSH/plugins/nvm/nvm.plugin.zsh
T=$(mktemp -d "$TMPDIR/nvm.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p $T/nvm $T/home $T/project $T/other
log=$T/nvm.log

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [$2]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

print -r -- 'NVM_SOURCED=1
nvm_find_nvmrc() { [[ -f $PWD/.nvmrc ]] && print -r -- $PWD/.nvmrc }
nvm() {
  print -r -- "nvm $*" >> '$log'
  if [[ "$*" == "version default" ]]; then print -r -- v18
  elif [[ $1 == version ]]; then print -r -- N/A; fi
}' > $T/nvm/nvm.sh
print 20 > $T/project/.nvmrc

run() {
  ( HOME=$T/home; unset NVM_DIR NVM_HOMEBREW XDG_CONFIG_HOME; : > $log; eval "$1" )
}

run '
  export NVM_DIR=$T/nvm
  source $plugin
  eq "success: nvm.sh sourced eagerly" "$NVM_SOURCED" 1
  eq "success: completion helper removed" $+functions[_omz_nvm_setup_completion] 0
  eq "success: autoload helper removed" $+functions[_omz_nvm_setup_autoload] 0
  eq "success: autoload off defines no load-nvmrc" $+functions[load-nvmrc] 0
  eq "success: autoload off calls nvm never" "$(<$log)" ""
'

run '
  export NVM_DIR=$T/nvm
  cd $T/project
  zstyle ":omz:plugins:nvm" autoload yes
  source $plugin
  eq "success: autoload on defines load-nvmrc" $+functions[load-nvmrc] 1
  eq "success: autoload on registers chpwd hook" "${chpwd_functions[(r)load-nvmrc]}" load-nvmrc
  eq "success: autoload helper removed after use" $+functions[_omz_nvm_setup_autoload] 0
  eq "success: missing node version triggers install" "$(<$log)" "nvm version 20
nvm install"
'

run '
  export NVM_DIR=$T/nvm
  cd $T/other
  zstyle ":omz:plugins:nvm" autoload yes
  source $plugin
  eq "edge: no .nvmrc anywhere never calls nvm" "$(<$log)" ""
'

run '
  export NVM_DIR=$T/nvm
  cd $T/project
  zstyle ":omz:plugins:nvm" autoload yes
  source $plugin
  : > $log
  cd $T/other
  eq "success: leaving a project reverts to the default version" "$(<$log)" "nvm version
nvm version default
nvm use default"
'

run '
  export NVM_DIR=$T/nvm
  cd $T/project
  zstyle ":omz:plugins:nvm" autoload yes
  zstyle ":omz:plugins:nvm" silent-autoload yes
  source $plugin
  eq "success: silent-autoload still installs" "$(<$log)" "nvm version 20
nvm install"
'

run '
  export NVM_DIR=$T/nvm
  zstyle ":omz:plugins:nvm" lazy yes
  source $plugin
  eq "success: lazy leaves nvm.sh unsourced" "${NVM_SOURCED-unset}" unset
  eq "success: lazy defines the node stub" $+functions[node] 1
  node --version 2>/dev/null
  eq "success: first use sources nvm.sh" "$NVM_SOURCED" 1
  eq "success: first use removes the node stub" $+functions[node] 0
'

run '
  nvm() { :; }
  export NVM_DIR=$T/nvm
  source $plugin
  eq "edge: existing nvm short-circuits the plugin" "${NVM_SOURCED-unset}" unset
'

run '
  source $plugin
  eq "edge: no NVM_DIR and no install leaves nvm unloaded" "${NVM_SOURCED-unset}${NVM_DIR-}" unset
'

run '
  mkdir -p $HOME/.nvm
  cp $T/nvm/nvm.sh $HOME/.nvm/nvm.sh
  source $plugin
  eq "success: defaults to ~/.nvm" "${NVM_DIR#$T/}" home/.nvm
'

run '
  export NVM_DIR=$T/empty
  source $plugin
  eq "edge: NVM_DIR without nvm.sh is ignored" "${NVM_SOURCED-unset}" unset
'
