# R14-T014 Evidence: `plugins/autojump`

## Command to run

```bash
zsh -n plugins/autojump/autojump.plugin.zsh && python3 work/R14-T014/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/autojump/tests/autojump.test.zsh
```

## What was tested

`plugins/autojump/tests/autojump.test.zsh` tests `plugins/autojump/autojump.plugin.zsh` inside a `zsh -f` sandbox with a `HOME` containing spaces and glob metacharacters (`home dir [x]*`), a decoy folder (`home dir xdecoy`), a stub `brew` printing a prefix with spaces and `[y]*`, and an empty `PATH` directory:

1. `[success]` **HOME containing spaces and [x]* sources exact autojump.zsh without touching decoy**: sources the fixture script under `$HOME/.autojump/etc/profile.d/autojump.zsh`, checks `AUTOJUMP_MARKER` equals that exact path, confirms `AUTOJUMP_DECOY` stays unset and the decoy file is untouched, and asserts `autojump_paths`, `file`, and `found` are unset afterwards.
2. `[success]` **brew --prefix fallback handles prefix with spaces and passes single --prefix arg**: with no fixture under `HOME`, invokes the `brew` stub, asserts `argc=1` (`--prefix`), checks `AUTOJUMP_BREW_MARKER` equals `<sandbox>/brew prefix [y]*/etc/profile.d/autojump.sh`, and checks locals are cleaned up.
3. `[edge]` **quoted paths survive sh_word_split and glob_subst without expanding into decoy**: runs Case 1 with `setopt sh_word_split glob_subst` (which failed with exit `126`, `"no matches found"`, and leaked `autojump_paths` on the unpatched plugin) and asserts it passes cleanly with no decoy expansion.
4. `[edge]` **pre-existing found=1 still initializes found=0 and reports missing autojump**: sets `found=1` before sourcing with nothing installed and no `brew` (which silently suppressed the error message on the unpatched plugin) and asserts stdout is `[oh-my-zsh] autojump not found. Please install it first.`, exit `0`, and `found` unset.
5. `[edge]` **missing autojump and brew prints install notice, exits 0, and cleans up locals**: verifies clean missing-tool notice, exit `0`, and unset local variables.

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| Pre-fix `autojump.test.zsh` run | Case 3 (`sh_word_split glob_subst`) and Case 4 (`found=1`) fail | Case 3 failed (`st=126`, `no matches found`, leaked `autojump_paths`) and Case 4 failed (empty stdout) |
| Post-fix `zsh -n plugins/autojump/autojump.plugin.zsh && python3 work/R14-T014/check.py` | Exit `0`, 5 cases (`2` success, `3` edge), `0` failures, clean sandbox | Exit `0`, 5 cases (`2` success, `3` edge), `0` failures, all 9 assertions `ok` |
| Negative check (expected `--prefix` changed to `--broken`) | Non-zero exit (`1`) | Exit `1` (`5 tests, 1 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
