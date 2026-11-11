# R14-T016 Evidence: `plugins/zoxide`

## Command to run

```bash
zsh -n plugins/zoxide/zoxide.plugin.zsh && python3 work/R14-T016/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/zoxide/tests/zoxide.test.zsh
```

## What was tested

`plugins/zoxide/tests/zoxide.test.zsh` runs in an isolated `zsh -f` sandbox with temporary `HOME`, `ZDOTDIR`, `ZSH_CACHE_DIR`, and a private `PATH` switching between a stubbed `zoxide` directory and an empty directory (`empty_bin`). Characterization tests were committed first against the untouched plugin, then re-run after refactoring `plugins/zoxide/zoxide.plugin.zsh` to use an early-return guard clause for the missing-tool check (`(( ! $+commands[zoxide] ))`).

1. `[success]` **unset ZOXIDE_CMD_OVERRIDE uses default z and evaluates zoxide init output**: exits `0`, passes `init --cmd z zsh` to the stub, and sets `ZOXIDE_FIXTURE=loaded`.
2. `[success]` **ZOXIDE_CMD_OVERRIDE=j passes j to --cmd**: exits `0`, passes `init --cmd j zsh`, and sets `ZOXIDE_FIXTURE=loaded`.
3. `[edge]` **empty ZOXIDE_CMD_OVERRIDE falls back to z**: exits `0`, passes `init --cmd z zsh` even when `ZOXIDE_CMD_OVERRIDE=""`, and sets `ZOXIDE_FIXTURE=loaded`.
4. `[edge]` **ZOXIDE_CMD_OVERRIDE with spaces arrives as one argument**: exits `0`, passes `my cd` as a single `--cmd` argument, and sets `ZOXIDE_FIXTURE=loaded`.
5. `[edge]` **missing zoxide prints install hint, exits 0, and leaves ZOXIDE_FIXTURE unset**: exits `0` with empty `empty_bin`, prints the install message on stdout, writes nothing to the stub log, and leaves `ZOXIDE_FIXTURE` unset (`__UNSET__`).

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| Pre-refactor characterization run | Exit `0`, 5 cases (`2` success, `3` edge), `0` failures | Exit `0`, 5 cases (`2` success, `3` edge), `0` failures |
| Post-refactor run (`zsh -n ... && python3 work/R14-T016/check.py`) | Identical stdout/exit status (`0`) and clean sandbox | Identical 5-case output, exit `0`, all 9 checks `ok` |
| Negative check (`z` changed to `broken` in `zoxide.test.zsh`) | Non-zero exit (`1`) | Exit `1` (`5 tests, 1 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
