# R14-T015 Evidence: `plugins/git`

## Command to run

```bash
zsh -n plugins/git/git.plugin.zsh && python3 work/R14-T015/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/git/tests/git.test.zsh
```

## What was tested

`plugins/git/tests/git.test.zsh` runs in an isolated `zsh -f` sandbox with `compinit -D`, `$ZSH/lib/git.zsh`, empty `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM=1`, temporary `HOME`/`ZDOTDIR`/`ZSH_CACHE_DIR`, and a stub `git` on `PATH` (never calling real `/usr/bin/git` or reading user/system git config):

1. `[edge]` **missing git loads cleanly, g exits 127, and grt returns 0 in place**: sources `git.plugin.zsh` with `empty_bin` on `PATH`, confirming loading succeeds (`0`), `g status` fails (`127`, `command not found: git`), `grt` stays in `$PWD` and returns `0`, and `gfa` keeps `--jobs=10` when `git_version` is empty (`is-at-least 2.8 ""` compares against `$ZSH_VERSION`, recorded as observed behavior).
2. `[edge]` **gfa adapts --jobs=10 based on stubbed git version (2.7.0 vs 2.45.1)**: sets the `git` stub to report `2.7.0` (`gfa='git fetch --all --tags --prune'`) and `2.45.1` (`gfa='git fetch --all --tags --prune --jobs=10'`).
3. `[success]` **g preserves quoted spaced filenames across stub boundary**: calls `g status -sb "file with space.txt"` and checks the stub received 3 separate arguments with the spaced filename intact.
4. `[success]` **grt changes PWD from subfolder to repository root**: runs `grt` inside `<sandbox>/repo/sub/deep`, asserting resolved `$PWD` moves to `<sandbox>/repo`.
5. `[success]` **ggpur resolves current branch and accepts explicit branch argument**: runs `ggpur` (calls `symbolic-ref --quiet HEAD` -> `feature/login`, then `pull --rebase origin feature/login`) and `ggpur release/1.0` (`pull --rebase origin release/1.0`).
6. `[edge]` **grt outside a repository stays in PWD and returns 0**: runs `grt` when `git rev-parse --show-toplevel` exits `128`, confirming `$PWD` remains `<sandbox>/outside` and exit status is `0`.

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| `zsh -n plugins/git/git.plugin.zsh && python3 work/R14-T015/check.py` | Exit `0`, 6 cases (`3` success, `3` edge), `0` failures, clean sandbox | Exit `0`, 6 cases (`3` success, `3` edge), `0` failures, all 10 assertions `ok` |
| Negative check (expected `gfa` for `2.7.0` appended with `--wrong`) | Non-zero exit (`1`) | Exit `1` (`6 tests, 1 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
