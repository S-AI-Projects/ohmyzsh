# R14-T044 — Path-quoting tests: `plugins/gh`

**Student:** Navee Prajapati  
**Task:** R14-T044 (Issue #45)  
**Branch:** `student/e26b07f0760/R14-T044`

## What was done

### 1. Source/documentation change
Added a **Path quoting** section to `plugins/gh/README.md` documenting that:
- `ZSH_CACHE_DIR` paths containing spaces are handled correctly.
- The `gh completion --shell zsh` args are passed as exact quoted strings — wildcard characters in arguments are not glob-expanded.

### 2. Automated check (`work/R14-T044/check.py`)

| # | Type | Assertion |
|---|------|-----------|
| Syntax | pass | `zsh -n plugins/gh/gh.plugin.zsh` exits 0 |
| Test 1 | success | Simple cache dir: `gh completion --shell zsh` exact args; `_gh` file written; exit 0 |
| Test 2 | edge/spaces | `ZSH_CACHE_DIR` with spaces: completion file still written correctly |
| Test 3 | boundary/wildcard | `gh` arg containing `*` is NOT glob-expanded; literal string preserved |
| Test 4 | boundary/unrelated | Unrelated files in cache dir unchanged after plugin load |

All external commands (`gh`, `zf_mv`, `autoload`, `zmodload`) are stubbed.
All state changes are isolated inside `tempfile.TemporaryDirectory()` sessions.
No real GitHub CLI or user configuration is modified.

## Running the checks

```zsh
zsh -n plugins/gh/gh.plugin.zsh && python3 work/R14-T044/check.py
```

## Tool versions

```
zsh 5.9 (arm64-apple-darwin25.0)
Python 3.15.2
```

## Check output (captured)

```
============================================================
R14-T044 · Path-quoting tests: plugins/gh
Entry points: gh completion --shell zsh (completion init)
============================================================

[Syntax] zsh -n plugins/gh/gh.plugin.zsh
  PASS  plugin passes zsh -n syntax check

[Test 1] SUCCESS — simple cache dir; completion args exact; file written
  PASS  exit status 0
  PASS  gh called with 'completion'
  PASS  gh called with '--shell'
  PASS  gh called with 'zsh'
  PASS  completion file written to cache dir
        gh argv    : ['completion', '--shell', 'zsh']
        comp file  : exists
        exit status: 0

[Test 2] EDGE — ZSH_CACHE_DIR contains spaces; completion file still written
  PASS  exit status 0
  PASS  completion file written (path with spaces)
        cache dir  : '.../my cache dir with spaces'
        comp file  : exists
        exit status: 0

[Test 3] BOUNDARY — gh arg containing wildcard '*' is NOT glob-expanded
  PASS  exit status 0
  PASS  wildcard arg preserved as literal (not glob-expanded)
  PASS  no decoy filenames appear in argv (glob not expanded)
        gh argv    : ['pr', 'list', '--search', 'type:pr *.yaml']
        exit status: 0

[Test 4] BOUNDARY — unrelated cache files unchanged after plugin loads
  PASS  exit status 0
  PASS  unrelated file still exists
  PASS  unrelated file content unchanged
        unrelated file : _kubectl
        content intact : True
        exit status    : 0

============================================================
RESULT: All checks PASSED
============================================================
```
