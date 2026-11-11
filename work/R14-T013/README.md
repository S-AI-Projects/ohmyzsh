# R14-T013 Evidence: `plugins/git-lfs`

## Command to run

```bash
zsh -n plugins/git-lfs/git-lfs.plugin.zsh && python3 work/R14-T013/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/git-lfs/tests/git-lfs.test.zsh
```

## What was tested

`plugins/git-lfs/tests/git-lfs.test.zsh` runs in an isolated `zsh -f` sandbox with temporary `HOME`, `ZDOTDIR`, `ZSH_CACHE_DIR`, and a stub `git` on `PATH` (never calling real `git` or `git-lfs`), recording shell definitions and directory files before and after each transition:

1. `[success]` **sourcing plugin adds 4 git-lfs aliases and preserves unrelated alias ll**: checks `glfsi`, `glfst`, `glfsls`, `glfsmi` were undefined before sourcing, confirms all 4 match their definitions afterwards, verifies the alias count grows by exactly `4` (`3` → `7`), and confirms pre-existing `ll='ls -l'` stays unchanged.
2. `[success]` **glfst preserves quoted wildcards/spaces, updates .gitattributes (simulated), and leaves a.psd untouched**: passes `"*.psd"` and `"design files/*.ai"` without glob expansion to the `git` stub; the stub simulates `git lfs track` by appending LFS filter lines to `.gitattributes` while decoy file `a.psd` stays unchanged.
3. `[success]` **glfsls forwards lfs ls-files and leaves PWD and files unchanged**: asserts `git` stub receives `lfs` + `ls-files`, `$PWD` stays unchanged, and the directory file list (`.gitattributes`, `a.psd`) stays unchanged.
4. `[success]` **gplfs resolves branch via git_current_branch and calls git lfs push origin feature/login --all**: sources `$ZSH/lib/git.zsh` with the `git` stub returning `refs/heads/feature/login` for `symbolic-ref --quiet HEAD`, confirming `gplfs` invokes `git lfs push origin feature/login --all`.
5. `[edge]` **glfsi propagates status 1 on failure and leaves aliases and files unchanged**: configures the `git` stub to exit `1` (missing `git-lfs` subcommand), confirming `glfsi` returns `1` while all alias definitions and files remain unchanged.

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| `zsh -n plugins/git-lfs/git-lfs.plugin.zsh && python3 work/R14-T013/check.py` | Exit `0`, 5 cases (`4` success, `1` edge), `0` failures, clean sandbox | Exit `0`, 5 cases (`4` success, `1` edge), `0` failures, all 10 assertions `ok` |
| Negative check (expected alias delta `4` changed to `3`) | Non-zero exit (`1`) | Exit `1` (`5 tests, 1 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
