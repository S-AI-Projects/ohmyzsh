# R14-T012 Evidence: `plugins/cp`

## Command to run

```bash
zsh -n plugins/cp/cp.plugin.zsh && python3 work/R14-T012/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/cp/tests/cp.test.zsh
```

## What was tested

`plugins/cp/tests/cp.test.zsh` runs in an isolated `zsh -f` sandbox with `compinit -D`, private `HOME`/`ZDOTDIR`/`ZSH_CACHE_DIR`, and a stub `rsync` that logs `argc` and every argument line-by-line while returning a configured exit code. (Because `rsync` is stubbed, the remote-path case proves what arguments `cpv` sends—including `-e /dev/null`—and that `cpv` propagates `rsync`'s non-zero exit code without invoking real `rsync`.)

1. `[success]` **compdef registers _files completion for cpv**: sources `cp.plugin.zsh` after `compinit -D` and asserts `$_comps[cpv] == _files` with exit status `0` and empty stderr.
2. `[success]` **minimum argument list cpv src.txt dest/ forwards 6 fixed options plus 2 paths**: asserts `argc=8` with `-pogbr`, `-hhh`, `--backup-dir=/tmp/rsync-$USERNAME`, `-e`, `/dev/null`, `--progress`, source, destination, exit `0`, and unchanged source/backup-dir state.
3. `[success]` **optional -n flag, spaced path, and literal wildcard arrive as separate arguments**: asserts `argc=10` with `-n`, spaced directory path, and unexpanded `*.txt` wildcard each forwarded as one distinct argument.
4. `[edge]` **documented invalid remote path host:/src preserves -e /dev/null and returns rsync status 12**: configures the `rsync` stub to exit `12` and verifies `-e` + `/dev/null` remain present and `cpv` returns `12` unchanged.
5. `[edge]` **missing rsync executable exits 127 and leaves files untouched**: invokes `cpv` with an empty `PATH`, asserting exit `127`, `command not found: rsync` on stderr, empty stub log, and unchanged source file.

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| `zsh -n plugins/cp/cp.plugin.zsh && python3 work/R14-T012/check.py` | Exit `0`, 5 cases (`3` success, `2` edge), `0` failures, clean sandbox | Exit `0`, 5 cases (`3` success, `2` edge), `0` failures, all 10 assertions `ok` |
| Negative check (expected remote exit `12` changed to `0`) | Non-zero exit (`1`) | Exit `1` (`5 tests, 1 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
