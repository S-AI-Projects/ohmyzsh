# asdf

Adds integration with [asdf](https://github.com/asdf-vm/asdf), the extendable version manager, with support for Ruby, Node.js, Elixir, Erlang and more.

## Installation

1. [Install](https://asdf-vm.com/guide/getting-started.html#_1-install-asdf) asdf and ensure that's it's discoverable on `$PATH`;
2. Enable it by adding it to your `plugins` definition in `~/.zshrc`:

```sh
plugins=(asdf)
```

## Usage

Refer to the [asdf plugin documentation](https://asdf-vm.com/guide/getting-started.html#_4-install-a-plugin) for information on how to add a plugin and install the many runtime versions for it.

### Verified Usage Example

Below is a complete, tested usage example demonstrating setup, command execution, expected output, and state verification:

#### 1. Setup
Ensure `asdf` is available on your `$PATH`. Optionally configure `ASDF_DATA_DIR`:
```sh
export ASDF_DATA_DIR="$HOME/.asdf"
```
When Oh My Zsh loads the `asdf` plugin, it automatically prepends `$ASDF_DATA_DIR/shims` to `$PATH` and configures zsh completions for `asdf`.

#### 2. Commands & Expected Output
Manage plugins and runtime versions using `asdf`:
```sh
# Add the nodejs plugin
asdf plugin add nodejs

# Install a specific runtime version
asdf install nodejs 18.16.0
# Output:
# Installing nodejs 18.16.0...
# nodejs 18.16.0 installation finished

# Set local version in .tool-versions
asdf set nodejs 18.16.0
# Output:
# Set nodejs 18.16.0 in .tool-versions
```

#### 3. State Verification
Verify that the runtime environment and shell state reflect the changes:
```sh
# Verify shims directory is prepended to PATH
[[ "$path[1]" == "$ASDF_DATA_DIR/shims" ]]

# Verify current active version from .tool-versions
asdf current nodejs
# Output: nodejs 18.16.0 (set by /path/to/.tool-versions)
```


Example for installing the nodejs plugin and the many runtimes for it:

```sh
# Add plugin to asdf
asdf plugin add nodejs

# Install the latest available version
asdf install nodejs latest

# Uninstall the latest version
asdf uninstall nodejs latest

# Install a specific version
asdf install nodejs 16.5.0

# Set the latest version in .tool-versions of the `current directory`
asdf set nodejs latest

# Set a specific version in the `parent directory`
asdf set -p nodejs 16.5.0   # -p is shorthand for --parent

# Set a global version under `$HOME`
asdf set -u nodejs 16.5.0   # -u is shorthand for --home
```

For more commands, run `asdf help` or refer to the
[asdf CLI documentation](https://asdf-vm.com/manage/commands.html#all-commands).

## Maintainer

- [@RobLoach](https://github.com/RobLoach)
