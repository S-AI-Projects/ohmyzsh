# R14-T017 Evidence: `plugins/history`

## Command to run

```bash
zsh -n plugins/history/history.plugin.zsh && python3 work/R14-T017/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/history/tests/history.test.zsh
```

## What was tested

`plugins/history/tests/history.test.zsh` runs in an isolated `zsh -f` sandbox with temporary `HOME`, `ZDOTDIR`, `ZSH_CACHE_DIR`, and a private `PATH` containing only `grep` and `less` stubs that log `argc` and every argument line-by-line. It reads the tagged `Setup`, `Command`, `Output`, and `State verification` code blocks directly from `plugins/history/README.md` and verifies:

1. `[success]` **README example command output matches README output block** (`hs git`): exits `0`, passes `argc=1` (`git`) to `grep`, matches the documented output block byte-for-byte, and leaves the 3 seeded history events unchanged.
2. `[success]` **README state verification h lists all three setup events unchanged** (`h`): exits `0`, matches the documented verification output block byte-for-byte, calls no external stub, and leaves the 3 history events unchanged.
3. `[success]` **hl pipes full history into less stub with zero arguments** (`hl`): exits `0`, pipes all 3 history events through the `less` stub receiving `argc=0`, and leaves history unchanged.
4. `[success]` **hsi searches history case-insensitively with grep -i** (`hsi GIT`): exits `0`, passes `argc=2` (`-i`, `GIT`) to `grep`, outputs both matching events, and leaves history unchanged.
5. `[edge]` **hs with no matching event prints nothing, returns 1, and preserves history** (`hs no-such-command`): exits `1`, emits empty stdout/stderr, passes `argc=1` (`no-such-command`) to `grep`, and leaves all 3 history events intact.

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| `zsh -n plugins/history/history.plugin.zsh` | Exit `0` | Exit `0` |
| `python3 work/R14-T017/check.py` | Exit `0`, 5 cases (`4` success, `1` edge), `0` failures, clean sandbox | Exit `0`, 5 cases (`4` success, `1` edge), `0` failures, all 10 assertions `ok` |
| Negative check (`1  git status` changed to `2  git status` in `plugins/history/README.md`) | Non-zero exit (`1`) when README output drifts | Exit `1` (`5 tests, 2 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
