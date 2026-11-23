# rsync

This plugin adds aliases for frequent [rsync](https://rsync.samba.org/) commands, simplifying file transfer and synchronization tasks.

To use it add `rsync` to the plugins array in you `.zshrc` file.

```zsh
plugins=(... rsync)
```

| Alias               | Command                                          | Description |
| ------------------- | ------------------------------------------------ | ------------|
| `rsync-copy`        | `rsync -avz --progress -h`                       | Recursively copy files and directories, preserving permissions, timestamps, and symbolic links. Compression is enabled for faster transfers. Progress is displayed in a human-readable format. | 
| `rsync-move`        | `rsync -avz --progress -h --remove-source-files` | Same as rsync-copy, but removes the source files after a successful transfer (effectively performing a move). | 
| `rsync-update`      | `rsync -avzu --progress -h`                      | Like rsync-copy, but only updates files if the source is newer than the destination (or if the destination file is missing). | 
| `rsync-synchronize` | `rsync -avzu --delete --progress -h`             | Performs bidirectional-style sync: updates files as in rsync-update and deletes files in the destination that no longer exist in the source. Useful for directory synchronization. | 

Explanation of Flags:
 - -a: Archive mode; preserves symbolic links, permissions, timestamps, etc.
 - -v: Verbose; shows details of the transfer process.
 - -z: Compress file data during transfer for efficiency.
 - -u: Skip files that are newer on the receiver.
 - --progress: Show progress during file transfer.
 - -h: Output numbers in human-readable format (e.g., 1K, 234M).
 - --remove-source-files: Deletes source files after they are copied (used in rsync-move).
 - --delete: Deletes files in the destination that are not present in the source (used in rsync-synchronize).

## Troubleshooting & Diagnostics

### Missing or Non-existent Source Path

A frequent cause of failure when using `rsync-copy` or `rsync-move` is targeting a source file or directory that does not exist or has an incorrect path:

```zsh
# Failing invocation (source directory does not exist):
$ rsync-copy missing_src/ backup/
rsync: [sender] change_dir "missing_src" failed: No such file or directory (2)
rsync error: some files/attrs were not transferred (see previous errors) (code 23)
```

**Diagnostic**:
1. Check rsync's exit code (`echo $?`). An exit code of `23` indicates partial transfer due to error or missing files/directories.
2. Verify that the source directory exists and is readable:
   ```zsh
   ls -ld missing_src/
   ```
3. Check for typos or missing parent paths before invoking transfer commands.

**Corrected Invocation**:
Ensure the source fixture or directory exists before running:
```zsh
mkdir -p valid_src && touch valid_src/item.txt
rsync-copy valid_src/ backup/
# Exits with status 0 and completes successfully
```

