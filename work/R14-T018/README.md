# R14-T018 Evidence: `plugins/fzf`

## Command to run

```bash
zsh -n plugins/fzf/fzf.plugin.zsh && python3 work/R14-T018/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/fzf/tests/fzf.test.zsh
```

## What was tested

`plugins/fzf/tests/fzf.test.zsh` tests `plugins/fzf/fzf.plugin.zsh` inside a `zsh -f` sandbox with `FZF_BASE` always pointed at controlled temporary folders (and `apt`, `apt-get`, `brew`, `fzf-share`, `fd`, `rg`, `ag` excluded from `PATH`) so host installations cannot interfere:

1. `[edge]` **empty FZF_BASE prints Cannot find diagnostic, leaves marker unset, and records PATH change**: sets `FZF_BASE` to an empty temporary folder with `nocmd_bin` (`cat` only), verifies `source` returns `0` after printing `no such file or directory` + `[oh-my-zsh] fzf plugin: Cannot find fzf installation directory.` on `stderr`, leaves `FZF_MARKER` unset, and records that `PATH` still gained `$FZF_BASE/bin`.
2. `[edge]` **fzf_setup_using_base_dir returns non-zero 127 when shell/key-bindings.zsh is absent**: evaluates the plugin function definitions up to the setup chain, calls `fzf_setup_using_base_dir` directly on `empty_base`, and asserts exit `127` with `key-bindings.zsh` in `stderr`.
3. `[success]` **corrected FZF_BASE containing shell/key-bindings.zsh succeeds with empty stderr**: points `FZF_BASE` at a folder containing `shell/key-bindings.zsh`, confirming `source` exits `0`, `stderr` is empty, and `FZF_MARKER=loaded_from_base` is set.
4. `[edge]` **fzf_setup_using_fzf returns 1 for fzf 0.47.0 without calling fzf --zsh**: provides a stub `fzf` reporting `0.47.0 (brew)`, verifying `fzf_setup_using_fzf` returns `1` and never invokes `--zsh`.
5. `[success]` **fzf 0.56.3 initializes via fzf --zsh cleanly even with empty FZF_BASE**: provides a stub `fzf` reporting `0.56.3 (brew)`, verifying full plugin sourcing calls `--version` then `--zsh` and sets `FZF_ZSH_MARKER=loaded_via_zsh_flag`.

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| `zsh -n plugins/fzf/fzf.plugin.zsh && python3 work/R14-T018/check.py` | Exit `0`, 5 cases (`2` success, `3` edge), `0` failures, clean sandbox | Exit `0`, 5 cases (`2` success, `3` edge), `0` failures, all 10 assertions `ok` |
| Negative check (expected `fzf_setup_using_base_dir` status `127` changed to `0`) | Non-zero exit (`1`) | Exit `1` (`5 tests, 1 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
