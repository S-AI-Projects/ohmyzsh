# R14-T050 · Regression mutation tests: `plugins/man`

**Student:** Navee Prajapati  
**Task:** R14-T050 (Issue #51)  
**Branch:** `student/e26b07f0760/R14-T050`

## What was done

### 1. Source / documentation clarification
- Clarified the inline comment in `plugins/man/man.plugin.zsh` for the prefix guard `[[ "$BUFFER" = man\ * ]]`, explaining why the space after `man` is essential to prevent erroneously matching commands like `manage.py`, `mandb`, or `manpath`.
- Expanded `plugins/man/README.md` with a **Behavior & Command Resolution** section documenting empty buffer handling, prefix matching behavior, and subcommand man page resolution.

### 2. Automated check (`work/R14-T050/check.py`)

| # | Type | Entry point | Assertion |
|---|------|-------------|-----------|
| Syntax | pass | — | `zsh -n plugins/man/man.plugin.zsh` exits 0 |
| Test 1 | success | `man-command-line` | Single command `ls -la` transforms to `man ls` (exit 0) |
| Test 2 | success | `man-command-line` | Subcommand `git commit -m initial` transforms to `man git commit` when `git-commit` man page exists |
| Test 3 | edge | `man-command-line` | Buffer `man grep` is left unmodified by the prefix guard |
| Test 4 | regression | `man-command-line` | Prefix command `manage.py runserver` is correctly transformed to `man manage.py` on unmutated code |
| Test 5 | mutant probe | probe | In a temporary copy, mutated `man\ *` to `man*`; verified `manage.py runserver` is falsely rejected, killing the mutant |
| Test 6 | edge | `man-command-line` | Empty buffer invokes `zle up-history` and prepends `man` to recalled command |

All external commands and ZLE functions are stubbed on a temporary `PATH`. All state transitions remain isolated inside `tempfile.TemporaryDirectory()` sessions. No real man command or user configuration is modified.

## Running the checks

```zsh
zsh -n plugins/man/man.plugin.zsh && python3 work/R14-T050/check.py
```

## Tool versions

```
zsh 5.9 (arm64-apple-darwin25.0)
Python 3.15.2
```

## Check output (captured)

```
============================================================
R14-T050 · Regression mutation tests: plugins/man
Target condition: [[ "$BUFFER" = man\ * ]]
============================================================

[Syntax] zsh -n plugins/man/man.plugin.zsh
  PASS  plugin passes zsh -n syntax check

[Test 1] SUCCESS - single command without subcommand man page
  PASS  exit status 0
  PASS  transforms 'ls -la' to 'man ls'
        buffer     : 'man ls'

[Test 2] SUCCESS - command with valid subcommand man page (git commit)
  PASS  exit status 0
  PASS  transforms to 'man git commit' when git-commit man page exists
        buffer     : 'man git commit'

[Test 3] EDGE - command already prefixed with 'man '
  PASS  exit status 0
  PASS  leaves buffer unchanged as 'man grep'
        buffer     : 'man grep' (early return)

[Test 4] REGRESSION - command starting with 'man' letters (manage.py)
  PASS  exit status 0
  PASS  correctly prepends man to 'manage.py' on unmutated code
        buffer     : 'man manage.py' ✓

[Test 5] MUTATION PROBE - verify mutant 'man*' is killed by manage.py test case
  PASS  mutant was killed: 'man*' prematurely returned on 'manage.py'
        mutant buf : 'manage.py runserver' (failed to prepend man)
        mutant kill: confirmed ✓

[Test 6] EDGE - empty buffer triggers zle up-history
  PASS  exit status 0
  PASS  invokes zle up-history when buffer is empty
  PASS  recalled command prepended with man
        history called: yes ✓
        recalled buf  : 'man echo' ✓

============================================================
RESULT: All checks PASSED
============================================================
```
