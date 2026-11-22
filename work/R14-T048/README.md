# R14-T048 · Failure diagnostics tests: `plugins/rails`

**Student:** Navee Prajapati  
**Task:** R14-T048 (Issue #49)  
**Branch:** `student/e26b07f0760/R14-T048`

## What was done

### 1. Source / documentation change
Added a **Troubleshooting & Diagnostics** section to `plugins/rails/README.md` explaining:
- The common failing invocation for `devlog` (`tail: log/development.log: No such file or directory`, exit code 1) when run prior to file initialization or outside the Rails root.
- The step-by-step resolution (`mkdir -p log && touch log/development.log`), demonstrating the corrected invocation succeeding afterwards (exit code 0).
- The resolution precedence order for `_rails_command` and `_rake_command`.

### 2. Automated check (`work/R14-T048/check.py`)

| # | Type | Entry point | Assertion |
|---|------|-------------|-----------|
| Syntax | pass | — | `zsh -n plugins/rails/rails.plugin.zsh` exits 0 |
| Test 1 | failure | `devlog` | Missing `log/development.log` fails with exit code 1 and error diagnostic on stderr |
| Test 2 | recovery | `devlog` | After creating `log/development.log`, invocation succeeds with exit code 0 |
| Test 3 | success | `rails` | `_rails_command` dispatches to local `bin/rails` binstub when present (exit 0) |
| Test 4 | success | `rails` | `_rails_command` falls back to system `rails` when no binstub exists (exit 0) |
| Test 5 | success | `rake` | `_rake_command` wraps with `bundle exec rake` when `Gemfile` is present (exit 0) |

All external commands (`tail`, `rails`, `rake`, `bundle`, `ruby`) are stubbed on a temporary `PATH`. All state transitions remain isolated inside `tempfile.TemporaryDirectory()` sessions. No real Rails application or user configuration is modified.

## Running the checks

```zsh
zsh -n plugins/rails/rails.plugin.zsh && python3 work/R14-T048/check.py
```

## Tool versions

```
zsh 5.9 (arm64-apple-darwin25.0)
Python 3.15.2
```

## Check output (captured)

```
============================================================
R14-T048 · Failure diagnostics tests: plugins/rails
Entry points: devlog, rails, rake
============================================================

[Syntax] zsh -n plugins/rails/rails.plugin.zsh
  PASS  plugin passes zsh -n syntax check

[Test 1 & 2] FAILURE & RECOVERY - devlog missing log file, then corrected
  PASS  missing log file produces non-zero exit status (1)
  PASS  stderr produces diagnostic message 'No such file or directory'
        failure verified: tail: log/development.log: No such file or directory
  PASS  corrected invocation succeeds with exit status 0
  PASS  tail received expected arguments ['-f', 'log/development.log']
        recovery verified: tail succeeded on log/development.log ✓

[Test 3] SUCCESS - _rails_command uses bin/rails when present
  PASS  exit status 0
  PASS  dispatches to local bin/rails binstub
        binstub dispatch: local bin/rails executed ✓

[Test 4] SUCCESS - _rails_command falls back to system rails when no binstub
  PASS  exit status 0
  PASS  falls back to system rails command
        fallback dispatch: system rails executed ✓

[Test 5] SUCCESS - _rake_command wraps with bundle exec when Gemfile present
  PASS  exit status 0
  PASS  bundle wrapper invoked
  PASS  arguments match bundle exec rake db:migrate
        bundle exec dispatch: bundle exec rake db:migrate ✓

============================================================
RESULT: All checks PASSED
============================================================
```
