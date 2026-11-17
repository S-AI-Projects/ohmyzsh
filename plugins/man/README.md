# Man plugin

This plugin adds a shortcut to insert man before the previous command.
The shortcut preserves quoted argument boundaries, including spaces and wildcard
characters, when it inserts the `man` command.

To use it, add `man` to the plugins array in your zshrc file:

```zsh
plugins=(... man)
```
# Keyboard Shortcuts
| Shortcut                          | Description                                                            |
|-----------------------------------|------------------------------------------------------------------------|
| <kbd>Esc</kbd> + man              | add man before the previous command to see the manual for this command |

## Tests

Run the isolated widget checks with:

```zsh
python3 work/R14-T004/check.py
```

The checks use a temporary directory and a stub `man` command; they do not run
the system manual viewer or change your shell configuration.
