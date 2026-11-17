# zoxide plugin

Initializes [zoxide](https://github.com/ajeetdsouza/zoxide), a smarter cd
command for your terminal.

![Tutorial](https://raw.githubusercontent.com/ajeetdsouza/zoxide/97dc08347d9dbf5b5a4516b79e0ac27366b962ce/contrib/tutorial.webp)

To use it, add `zoxide` to the plugins array in your `.zshrc` file:

```zsh
plugins=(... zoxide)
```
## Overriding `z` Alias

You can set the `ZOXIDE_CMD_OVERRIDE`, which will be passed to the `--cmd` flag of `zoxide init`. This allows you to set your `z` command to a default of `cd`.

**Note:** you have to [install zoxide](https://github.com/ajeetdsouza/zoxide#step-1-install-zoxide) first.

## Example: Add and Jump to a Project

After installing zoxide and enabling the plugin, add a project directory to
zoxide's database, jump to it with `z`, and verify the resulting directory with
`pwd`:

```zsh
# In ~/.zshrc:
plugins=(... zoxide)

# In a new terminal, register a project directory:
zoxide add "$HOME/src/my project"

# Jump to the project (the argument can be a unique part of its name):
z 'my project'
# /Users/avika/src/my project

# Verify the shell is now in that directory:
pwd
# /Users/avika/src/my project
```

The `z` command changes the current shell's working directory. The example
above is exercised by `tests/zoxide.test.zsh` using a temporary directory and
a stub `zoxide` command, so it does not require an installed zoxide database
or modify the user's shell configuration.
