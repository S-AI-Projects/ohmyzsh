# R14-T020 Evidence: `plugins/npm`

## Command to run

```bash
zsh -n plugins/npm/npm.plugin.zsh && python3 work/R14-T020/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/npm/tests/npm.test.zsh
```

## What was tested

`plugins/npm/tests/npm.test.zsh` initializes `compinit -D` inside an isolated `zsh -f` sandbox (with temporary `HOME`, `ZDOTDIR`, `ZSH_CACHE_DIR`, symlinked `rm`, and stub `npm`) and verifies both the presence and absence branches of `(( $+commands[npm] ))` as well as alias argument expansion:

1. `[success]` **when npm is present, stale cache file is deleted and _npm_completion is registered**: seeds `$ZSH_CACHE_DIR/npm_completion`, sources the plugin with stub `npm` on `PATH`, and asserts `$_comps[npm] == _npm_completion`, the stale cache file is removed, and `npmg` is defined.
2. `[edge]` **when npm is missing, completion is skipped, cache file is kept, and aliases remain defined**: seeds `$ZSH_CACHE_DIR/npm_completion`, sources the plugin with `no_npm_bin` (contains `rm`, no `npm`), and asserts `$_comps[npm]` stays `_npm`, the stale file survives, and `npmg`, `npmS`, and `npmD` are all defined.
3. `[success]` **npmD, npmS, and npmg preserve flags, quoted arguments, and trailing-space alias expansion**: invokes `npmD jest "my pkg"`, `npmS react`, `npmg typescript`, and `alias pk='left-pad'; npmg pk`, verifying exact argument vectors logged by the `npm` stub.
4. **Mutant rejection inside `check.py`**: copies `plugins/npm/npm.plugin.zsh` into a temporary directory, mutates `(( $+commands[npm] )) && {` to `(( ! $+commands[npm] )) && {` (verifying exactly 1 line differs), runs `npm.test.zsh` against the temporary mutant, and asserts non-zero exit (`1`) with both completion/cache cases failing.

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| `zsh -n plugins/npm/npm.plugin.zsh && python3 work/R14-T020/check.py` (real plugin) | Exit `0`, 3 cases (`2` success, `1` edge), `0` failures | Exit `0`, 3 cases (`2` success, `1` edge), `0` failures |
| Mutant run (`(( ! $+commands[npm] ))`) inside `check.py` | Non-zero exit (`1`), exactly 1 line changed | Exit `1` (`3 tests, 2 failures`), 1 line changed (line 2), all 11 assertions `ok` |
| Negative check (expected `comp=_npm_completion` changed to `comp=_wrong` in `npm.test.zsh`) | Non-zero exit (`1`) | Exit `1` (`3 tests, 1 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
