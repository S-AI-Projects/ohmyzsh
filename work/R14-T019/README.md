# R14-T019 Evidence: `plugins/docker`

## Command to run

```bash
zsh -n plugins/docker/docker.plugin.zsh && python3 work/R14-T019/check.py
```

Direct shell test invocation:

```bash
zsh -f plugins/docker/tests/docker.test.zsh
```

## What was tested

`plugins/docker/tests/docker.test.zsh` runs in an isolated `zsh -f` sandbox with temporary `HOME`, `ZDOTDIR`, `ZSH_CACHE_DIR`, an unusable `DOCKER_HOST=tcp://127.0.0.1:1`, and a stub `docker` binary (no Docker daemon required):

1. `[edge]` **missing docker defines aliases, leaves cache untouched, and dbl exits 127**: loads `docker.plugin.zsh` with `empty_bin` on `PATH`, verifying `dbl`, `dcin`, and `dcls` are still defined, `$ZSH_CACHE_DIR` remains empty, and running `dbl` fails with exit `127`.
2. `[success]` **docker 24.0.2 completion cache is generated cleanly via docker completion zsh**: loads `docker.plugin.zsh` with the `docker` stub reporting `Docker version 24.0.2, build cb74dfcd85`, waits up to 5 seconds for the background completion job, and verifies `$ZSH_CACHE_DIR/completions/_docker` contains the stub's `docker completion zsh` output with empty stderr (proving the `autoload -Uz is-at-least` fix works standalone without falling back to legacy completion).
3. `[success]` **dbl, dcin, and dcls preserve quoted arguments independent of Docker daemon**: executes `dbl -t "my image:1.0" "ctx dir/"`, `dcin web`, and `dcls -a`, asserting exact `argc` and `arg=` vectors while `DOCKER_HOST` points to `tcp://127.0.0.1:1`.
4. **Failure propagation in `check.py`**: copies `docker.plugin.zsh` into a temporary sandbox, replaces `alias dbl='docker build'` with `alias dbl='docker bild'`, runs `docker.test.zsh` against the broken copy, and asserts non-zero exit (`1`) and failing assertions while leaving the real repository sandbox clean.

## Expected versus actual results

| Check | Expected | Actual |
| --- | --- | --- |
| Pre-fix `docker.test.zsh` run | Background job fails `is-at-least` and copies legacy completion | `stderr: "(anon):8: command not found: is-at-least"`, legacy completion copied (`3 tests, 1 failures`) |
| Post-fix `zsh -n plugins/docker/docker.plugin.zsh && python3 work/R14-T019/check.py` | Exit `0`, 3 cases (`2` success, `1` edge), `0` failures, broken-plugin check exits `1`, clean sandbox | Exit `0`, 3 cases (`2` success, `1` edge), `0` failures, broken-plugin check exited `1` (`3 tests, 2 failures`), all 10 assertions `ok` |
| Negative check (expected `web` changed to `wrong` in `docker.test.zsh`) | Non-zero exit (`1`) | Exit `1` (`3 tests, 1 failures`), reverted immediately |
| Recorded files | `results.json` and `versions.txt` beside `check.py` | Written and verified on `zsh 5.9`, `python 3.14.7`, `macOS-27.2-arm64-arm-64bit-Mach-O` |
