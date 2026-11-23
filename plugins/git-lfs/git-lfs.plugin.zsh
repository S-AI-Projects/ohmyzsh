#
# Aliases
#

alias glfsi='git lfs install'
alias glfst='git lfs track'
alias glfsls='git lfs ls-files'
alias glfsmi='git lfs migrate import --include='

#
# Functions
#

function gplfs() {
  git lfs push origin "$(git_current_branch)" --all
}
