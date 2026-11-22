# Man plugin

This plugin adds a shortcut to insert man before the previous command.

To use it, add `man` to the plugins array in your zshrc file:

```zsh
plugins=(... man)
```

## Keyboard Shortcuts

| Shortcut             | Description                                                            |
|----------------------|------------------------------------------------------------------------|
| <kbd>Esc</kbd> + man | add man before the previous command to see the manual for this command |

## Behavior & Command Resolution

When the shortcut (<kbd>Esc</kbd> + `man`) is pressed:

1. **Empty Buffer**: If no command is currently typed on the command line, it recalls the previous command from history (`up-history`).
2. **Existing `man ` Guard**: If the buffer already begins with `man ` (`man\ *`), the widget returns early without modifying the buffer. Commands that begin with the letters `man` (such as `manage.py`, `mandb`, or `manpath`) are not matched by this guard and correctly have `man` prepended (e.g. `manage.py runserver` -> `man manage.py`).
3. **Subcommand Resolution**: Checks whether a hyphenated man page exists for the command and its first argument (e.g., `git-commit` for `git commit`). If found, it opens `man <command> <subcommand>`; otherwise it opens `man <command>`.
