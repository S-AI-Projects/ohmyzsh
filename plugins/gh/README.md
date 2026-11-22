# GitHub CLI plugin

This plugin adds completion for the [GitHub CLI](https://cli.github.com/).

To use it, add `gh` to the plugins array in your zshrc file:

```zsh
plugins=(... gh)
```

This plugin does not add any aliases.

## Path quoting

The plugin correctly handles `ZSH_CACHE_DIR` paths that contain **spaces** or
other special characters. The completion script is always written to:

```
$ZSH_CACHE_DIR/completions/_gh
```

regardless of whether the path contains spaces. The `gh completion --shell zsh`
invocation passes arguments as exact quoted strings — wildcard characters such
as `*` in any argument are **not** glob-expanded by the shell.

## Cache

This plugin caches the completion script and is automatically updated when the
plugin is loaded, which is usually when you start up a new terminal emulator.

The cache is stored at:

- `$ZSH_CACHE_DIR/completions/_gh` completions script
