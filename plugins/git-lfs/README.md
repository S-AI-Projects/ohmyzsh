# git lfs plugin

The git lfs plugin provides [aliases](#aliases) and [functions](#functions) for [git-lfs](https://github.com/git-lfs/git-lfs).

To use it, add `git-lfs` to the plugins array in your zshrc file:

```zsh
plugins=(... git-lfs)
```

## Aliases

| Alias    | Command                             |
| :------- | :---------------------------------- |
| `glfsi`  | `git lfs install`                   |
| `glfst`  | `git lfs track`                     |
| `glfsls` | `git lfs ls-files`                  |
| `glfsmi` | `git lfs migrate import --include=` |

## Functions

| Function | Command                                             |
| :------- | :-------------------------------------------------- |
| `gplfs`  | `git lfs push origin "$(git_current_branch)" --all` |

Note: `gplfs` requires `git_current_branch` (provided by Oh My Zsh's `lib/git.zsh`).

### Alias and Function Contracts

| Entry Point | Target Command | Description |
| :---------- | :------------- | :---------- |
| `glfsi`     | `git lfs install` | Installs Git LFS configuration hooks in repository. |
| `glfst`     | `git lfs track`   | Forwards tracked file pattern arguments intact (e.g. `glfst "*.psd"`). |
| `glfsls`    | `git lfs ls-files`| Lists Git LFS managed files with argument forwarding. |
| `glfsmi`    | `git lfs migrate import --include=` | Imports files into Git LFS with inclusion patterns. |
| `gplfs`     | `git lfs push origin "$(git_current_branch)" --all` | Pushes all LFS objects for the current branch to origin. |

