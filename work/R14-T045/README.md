# R14-T045 — Environment-isolation tests: `plugins/deno`

**Student:** Navee Prajapati  
**Task:** R14-T045 (Issue #46)  
**Branch:** `student/e26b07f0760/R14-T045`

## What was done

### 1. Source/documentation change
Updated `plugins/deno/README.md` alias table entries for `dc`, `dca`, and `dck`
to include explicit argument descriptions, making the contract clear to users.

### 2. Automated check (`work/R14-T045/check.py`)

| # | Type | Entry point | Assertion |
|---|------|-------------|-----------|
| Syntax | pass | — | `zsh -n plugins/deno/deno.plugin.zsh` exits 0 |
| Test 1 | success | `dc` | argv = `['compile', 'main.ts']`; isolated tmpdir; exit 0 |
| Test 2 | success | `dca` | argv = `['cache', 'deps.ts']`; exit 0 |
| Test 3 | success | `dck` | argv = `['check', 'mod.ts']`; exit 0 |
| Test 4 | missing-dep | guard | `deno` absent → completion skipped; `dc`/`dca`/`dck` aliases still defined |
| Test 5 | isolation | env | Outer `DENO_DIR` does not leak into isolated test env |

All external commands (`deno`, `zf_mv`) are replaced by stubs on a temporary PATH.
Each test runs in its own `tempfile.TemporaryDirectory()` with isolated `DENO_DIR`,
`DENO_INSTALL_ROOT`, `HOME`, and `ZSH_CACHE_DIR`. No real Deno installation,
network, or user configuration is modified.

## Running the checks

```zsh
zsh -n plugins/deno/deno.plugin.zsh && python3 work/R14-T045/check.py
```

## Tool versions

```
zsh 5.9 (arm64-apple-darwin25.0)
Python 3.15.2
```

## Check output (captured)

```
============================================================
R14-T045 · Environment-isolation tests: plugins/deno
Entry points: dc (deno compile), dca (deno cache), dck (deno check)
============================================================

[Syntax] zsh -n plugins/deno/deno.plugin.zsh
  PASS  plugin passes zsh -n syntax check

[Test 1] dc — deno compile <file>; exit 0
  PASS  exit status 0
  PASS  argv == ['compile', 'main.ts']
        deno argv  : ['compile', 'main.ts']
        workdir    : isolated tmpdir
        exit status: 0

[Test 2] dca — deno cache <file>; exit 0
  PASS  exit status 0
  PASS  argv == ['cache', 'deps.ts']
        deno argv  : ['cache', 'deps.ts']
        exit status: 0

[Test 3] dck — deno check <file>; exit 0
  PASS  exit status 0
  PASS  argv == ['check', 'mod.ts']
        deno argv  : ['check', 'mod.ts']
        exit status: 0

[Test 4] MISSING-DEP — deno absent; completion skipped; aliases still defined
  PASS  exit status 0
  PASS  alias dc still defined (declared before guard)
  PASS  completion file absent (guard returned early)
        alias dc   : defined
        completion : absent (correct)
        exit status: 0

[Test 5] ISOLATION — outer DENO_DIR does not leak into isolated test
  PASS  exit status 0
  PASS  DENO_DIR inside test is isolated tmpdir (not outer value)
        inner DENO_DIR : '.../r14t045_.../deno_dir'
        outer DENO_DIR : '.../r14t045_.../outer_deno_dir'
        isolated       : True
        exit status    : 0

============================================================
RESULT: All checks PASSED
============================================================
```
