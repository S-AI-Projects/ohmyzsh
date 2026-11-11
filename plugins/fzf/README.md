# fzf

This plugin tries to find [junegunn's fzf](https://github.com/junegunn/fzf) based on where
it's been installed, and enables its fuzzy auto-completion and key bindings.

To use it, add `fzf` to the plugins array in your zshrc file:

```zsh
plugins=(... fzf)
```

## Settings

All these settings should go in your zshrc file, before Oh My Zsh is sourced.

### `FZF_BASE`

Set to fzf installation directory path:

```zsh
export FZF_BASE=/path/to/fzf/install/dir
```

### `FZF_DEFAULT_COMMAND`

Set default command to use when input is tty:

```zsh
export FZF_DEFAULT_COMMAND='<your fzf default command>'
```

If not set, the plugin will try to set it to these, in the order in which they're found:

- [`fd`](https://github.com/sharkdp/fd)
- [`rg`](https://github.com/BurntSushi/ripgrep)
- [`ag`](https://github.com/ggreer/the_silver_searcher)

### `DISABLE_FZF_AUTO_COMPLETION`

Set whether to load fzf auto-completion:

```zsh
DISABLE_FZF_AUTO_COMPLETION="true"
```

### `DISABLE_FZF_KEY_BINDINGS`

Set whether to disable key bindings (CTRL-T, CTRL-R, ALT-C):

```zsh
DISABLE_FZF_KEY_BINDINGS="true"
```

## Troubleshooting

If loading the plugin prints:

```text
[oh-my-zsh] fzf plugin: Cannot find fzf installation directory.
Please add `export FZF_BASE=/path/to/fzf/install/dir` to your .zshrc
```

all setup helpers returned non-zero. The plugin tries them in this order:

1. `fzf --zsh` via `fzf_setup_using_fzf` (requires `fzf` `0.48.0` or newer on `PATH`; older versions return `1` and fall through).
2. Platform/distro helpers (`openbsd`, `debian`, `opensuse`, `fedora`, `cygwin`, `macports`).
3. Base-directory lookup (`fzf_setup_using_base_dir`): uses `FZF_BASE` if set to an existing directory, otherwise searches common install prefixes, `fzf-share`, or `brew --prefix fzf`, and sources `shell/key-bindings.zsh` (or `key-bindings.zsh` directly) from that directory.

Even when `FZF_BASE` is already set, `fzf_setup_using_base_dir` still fails (exit `127`) if that directory does not contain `shell/key-bindings.zsh` or `key-bindings.zsh` (and still appends `$FZF_BASE/bin` to `PATH` before sourcing fails).

**How to fix it:**

- Point `FZF_BASE` to the directory that contains `shell/key-bindings.zsh` (or `key-bindings.zsh`), **or**
- Install `fzf` `0.48.0` or newer on `PATH` so `fzf --zsh` is used directly without needing `FZF_BASE`.
