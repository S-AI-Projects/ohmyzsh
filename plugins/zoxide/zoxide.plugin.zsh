# Handle the missing-tool prerequisite upfront so the main init path stays flat.
if (( ! $+commands[zoxide] )); then
  echo '[oh-my-zsh] zoxide not found, please install it from https://github.com/ajeetdsouza/zoxide'
  return
fi

eval "$(zoxide init --cmd ${ZOXIDE_CMD_OVERRIDE:-z} zsh)"
