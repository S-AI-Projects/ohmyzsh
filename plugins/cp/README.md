# cp plugin

This plugin defines a `cpv` function that uses `rsync` so that you
get the features and security of this command.

To enable, add `cp` to your `plugins` array in your zshrc file:

```zsh
plugins=(... cp)
```

## Usage

Minimum invocation:

```zsh
cpv <source> <destination>
```

Any additional `rsync` options or source paths are forwarded unchanged after the fixed flags:

```zsh
cpv -n "dir with space/" dest/
```

Remote paths (such as `host:/src` or `user@host:/src`) are not supported because `-e /dev/null` disables remote shells; invoking `cpv` with a remote specification passes `-e /dev/null` to `rsync` and propagates its non-zero exit status. Because `cp` registers file completion with `compdef _files cpv`, `compinit` must be initialized before loading the plugin standalone.

## Description

The enabled options for rsync are:

- `-p`: preserves permissions.

- `-o`: preserves owner.

* `-g`: preserves group.

* `-b`: make a backup of the original file instead of overwriting it, if it exists.

* `-r`: recurse directories.

* `-hhh`: outputs numbers in human-readable format, in units of 1024 (K, M, G, T).

* `--backup-dir="/tmp/rsync-$USERNAME"`: move backup copies to "/tmp/rsync-$USERNAME".

* `-e /dev/null`: only work on local files (disable remote shells).

* `--progress`: display progress.
