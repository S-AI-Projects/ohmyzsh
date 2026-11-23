# R14-T028 · rsync Plugin Failure Diagnostics & Argument Preservation

## Overview

- **Item**: `rsync`
- **Plugin Path**: `plugins/rsync/rsync.plugin.zsh`
- **Documentation**: `plugins/rsync/README.md`
- **Task Type**: Failure Diagnostics & Argument Contract Preservation
- **Assigned Branch**: `student/e26b07f0722/R14-T028`

## Actual Entry Points

| Alias | Target Command | Description |
|---|---|---|
| `rsync-copy` | `rsync -avz --progress -h` | Recursively copies files/dirs with compression and human-readable progress |
| `rsync-move` | `rsync -avz --progress -h --remove-source-files` | Copies files/dirs and removes source files upon successful transfer |
| `rsync-update` | `rsync -avzu --progress -h` | Copies files/dirs updating newer/missing destination files |
| `rsync-synchronize` | `rsync -avzu --delete --progress -h` | Syncs directory, deleting orphaned files in destination |

## Failure Diagnostics & Corrected Invocation

### Failing Invocation
Targeting a non-existent directory triggers rsync error 23 (`some files/attrs were not transferred`):
```zsh
rsync-copy missing_src/ backup/
# rsync: [sender] change_dir "missing_src" failed: No such file or directory (2)
# rsync error: some files/attrs were not transferred (see previous errors) (code 23)
# exit status: 23
```

### Corrected Invocation
Creating or verifying the source path fixture allows the command to proceed successfully:
```zsh
mkdir -p valid_src && touch valid_src/item.txt
rsync-copy valid_src/ backup/
# sending incremental file list
# exit status: 0
```

## Test Harness & Verification

The suite runs in an isolated `ZDOTDIR` environment using a mock `rsync` binary stub that logs exact argument boundaries and exit codes.

### Test Matrix

| # | Test Name | Exit Code | Description |
|---|---|:---:|---|
| 1 | `sourcing_state_transition` | 0 | Verifies all 4 aliases are registered upon sourcing and unrelated aliases remain untouched |
| 2 | `failing_invocation_missing_source` | 23 | Validates failure branch when source directory is missing, confirming error diagnostic and code 23 |
| 3 | `corrected_invocation_success` | 0 | Validates that creating the fixture source directory yields a successful exit 0 with proper argument forwarding |
| 4 | `rsync_move_arguments_preservation` | 0 | Confirms `--remove-source-files` is preserved and forwarded |
| 5 | `rsync_update_arguments_preservation` | 0 | Confirms `-avzu` is preserved and forwarded |
| 6 | `rsync_synchronize_arguments_preservation` | 0 | Confirms `--delete` is preserved and forwarded |
| 7 | `documented_failure_invalid_option` | 1 | Confirms invalid options trigger failure exit code |
| 8 | `sandbox_state_isolation` | 0 | Ensures isolated `FAKE_HOME` does not leak into the host environment |

### Running the Checks

From the repository root:
```zsh
zsh -n plugins/rsync/rsync.plugin.zsh && python3 work/R14-T028/check.py
```
