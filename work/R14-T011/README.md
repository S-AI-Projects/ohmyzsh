# R14-T011 Evidence: `plugins/mvn`

## Command to run

```bash
zsh -n plugins/mvn/mvn.plugin.zsh && python3 work/R14-T011/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/mvn/tests/mvn.test.zsh
```

## What was tested

`plugins/mvn/tests/mvn.test.zsh` runs in an isolated `zsh -f` sandbox with temporary `HOME`, `ZDOTDIR`, `ZSH_CACHE_DIR`, and stub `mvn` / `mvnw` scripts, asserting output (`stdout`/`stderr`), exit status, and repository/shell state (`$PWD`, stub logs, and `${+dir}`) separately:

1. `[success]` **mvnboot -Dx="a b" from subfolder invokes executable root mvnw with 2 args and stderr notice**: from `<sandbox>/proj/sub/deep`, walks up to executable `<sandbox>/proj/mvnw`, prints ``Running `<sandbox>/proj/mvnw`...`` to `stderr`, forwards `spring-boot:run` and `-Dx=a b` as 2 args, leaves `mvn` uncalled, preserves `$PWD`, and leaves `${+dir} == 0`.
2. `[success]` **mvnag without mvnw falls back to mvn stub with archetype:generate and empty stderr**: in a tree without `mvnw`, calls `mvn` stub with `archetype:generate`, produces empty stdout/stderr, exits `0`, preserves `$PWD`, and leaves `${+dir} == 0`.
3. `[success]` **wrapper exit status 3 passes through mvnboot unchanged**: configures the `mvnw` stub to exit `3` and confirms `mvnboot` returns `3` with the expected wrapper invocation and stderr notice.
4. `[edge]` **non-executable mvnw is skipped and falls back to mvn stub**: when parent `mvnw` has mode `0644` (not executable), skips it and calls `mvn` stub with `-q`.
5. `[edge]` **bare mvn with no arguments forwards argc=0 to mvn stub**: runs `mvn` with zero args and confirms `argc=0` reaches the `mvn` stub.
6. `[edge]` **missing mvn on PATH without mvnw exits 127 and preserves shell state**: runs `mvn` with an empty `PATH`, asserting exit `127`, `command not found: mvn` on stderr, no stub calls, unchanged `$PWD`, and `${+dir} == 0`.

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| `zsh -n plugins/mvn/mvn.plugin.zsh && python3 work/R14-T011/check.py` | Exit `0`, 6 cases (`3` success, `3` edge), `0` failures, clean sandbox | Exit `0`, 6 cases (`3` success, `3` edge), `0` failures, all 10 assertions `ok` |
| Negative check (expected `mvnboot` status `3` changed to `0`) | Non-zero exit (`1`) | Exit `1` (`6 tests, 1 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
