# R14-T049 · Tooling integration tests: `plugins/composer`

**Student:** Navee Prajapati  
**Task:** R14-T049 (Issue #50)  
**Branch:** `student/e26b07f0760/R14-T049`

## What was done

### 1. Source / documentation change
Added a **Usage & Tooling Integration** section to `plugins/composer/README.md` documenting:
- The core entry point aliases: `c` (composer), `ccp` (composer create-project), and `cdo` (composer dump-autoload -o).
- Environment isolation and fallback paths when Composer is absent or when global binary directories are cached.

### 2. Automated check (`work/R14-T049/check.py`)

| # | Type | Entry point | Assertion |
|---|------|-------------|-----------|
| Syntax | pass | — | `zsh -n plugins/composer/composer.plugin.zsh` exits 0 |
| Test 1 | success | `c` | Expands to `composer` and forwards `['require', 'symfony/yaml']`; exit 0 |
| Test 2 | success | `ccp` | Expands to `composer create-project` and forwards `['create-project', 'laravel/laravel', 'myapp']`; exit 0 |
| Test 3 | success | `cdo` | Expands to `composer dump-autoload -o` and forwards `['dump-autoload', '-o']`; exit 0 |
| Test 4 | failure | status | Non-zero exit code (2) from composer propagates cleanly through alias `c` |
| Test 5 | edge | isolation | When `composer` is missing from `PATH`, plugin sources without error; aliases remain defined |
| Test 6 | cleanup | state | Temporary workspaces are verified removed from filesystem after run |

All external commands (`composer`, `php`, `curl`) are replaced by stubs on a temporary `PATH`. All state transitions remain isolated inside `tempfile.TemporaryDirectory()` sessions. No real Composer or PHP runtime is invoked.

## Running the checks

```zsh
zsh -n plugins/composer/composer.plugin.zsh && python3 work/R14-T049/check.py
```

## Tool versions

```
zsh 5.9 (arm64-apple-darwin25.0)
Python 3.15.2
```

## Check output (captured)

```
============================================================
R14-T049 · Tooling integration tests: plugins/composer
Entry points: c, ccp, cdo
============================================================

[Syntax] zsh -n plugins/composer/composer.plugin.zsh
  PASS  plugin passes zsh -n syntax check

[Test 1] SUCCESS - alias c expands to 'composer'
  PASS  exit status 0
  PASS  arguments received match ['require', 'symfony/yaml']
        composer argv: ['require', 'symfony/yaml']

[Test 2] SUCCESS - alias ccp expands to 'composer create-project'
  PASS  exit status 0
  PASS  arguments received match ['create-project', 'laravel/laravel', 'myapp']
        composer argv: ['create-project', 'laravel/laravel', 'myapp']

[Test 3] SUCCESS - alias cdo expands to 'composer dump-autoload -o'
  PASS  exit status 0
  PASS  arguments received match ['dump-autoload', '-o']
        composer argv: ['dump-autoload', '-o']

[Test 4] FAILURE - exit code propagates non-zero when composer fails
  PASS  non-zero exit code (2) propagates cleanly through alias c
        reported exit: 2 ✓

[Test 5] EDGE - plugin sourcing without composer dependency
  PASS  sourcing exits 0 when composer is not installed
  PASS  aliases c, ccp, cdo remain defined
        independent of composer installation: aliases defined ✓

[Test 6] CLEANUP - temporary state and directories are cleaned up
  PASS  command in temporary workspace ran successfully
  PASS  temporary workspace cleaned up cleanly
        cleanup verified: temporary directory removed ✓

============================================================
RESULT: All checks PASSED
============================================================
```
