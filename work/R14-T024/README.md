# R14-T024 — Path quoting and boundary checks: `plugins/ruby`

**Student:** Keshav Gupta  
**Task:** R14-T024 · 4 of 10 (Issue #27)  
**Branch:** `student/e26b07f0722/R14-T024`

## What was done

### 1. Source/documentation change
Updated `plugins/ruby/README.md` with an **Alias Argument Contract & Path Quoting** section documenting argument forwarding, path quoting, and wildcard preservation for `rb`, `sgem`, and `rfind`.

### 2. Automated check (`work/R14-T024/check.py`)

| # | Type | Entry point | Assertion Details |
|---|------|-------------|-------------------|
| Syntax | pass | `ruby.plugin.zsh` | `zsh -n` exits 0 |
| Test 1 | success / state | Sourcing | Aliases `rb`, `sgem`, `rfind` defined; unrelated aliases untouched |
| Test 2 | path quoting / wildcard | `rb` (`ruby`) | Path with spaces (`"lib dir with spaces"`) and wildcard (`"app folder/test_*.rb"`) preserved without word splitting; decoy files intact |
| Test 3 | path quoting / wildcard | `sgem` (`sudo gem`) | Quoted paths and wildcards forwarded to `sudo gem` intact; decoy files intact |
| Test 4 | wildcard / pipe | `rfind` | Pipeline forwards pattern with spaces and wildcards (`"def *initialize"`) to `grep -n` intact without premature expansion |
| Test 5 | documented edge / failure | `rb` | Invalid option (`--invalid-flag`) propagates exit 2 with error message |
| Test 6 | documented edge / failure | `sgem` | Underlying command failure exit code (1) propagates cleanly |
| Test 7 | state isolation | Sandbox check | Isolated sandbox `FAKE_HOME != HOME`; user environment untouched |

All external commands (`ruby`, `sudo`, `gem`, `find`, `grep`) are replaced by shell stubs on an isolated temporary PATH. Decoy files with spaces and wildcard patterns are tracked to confirm that shell globbing does not unintentionally alter or match unrelated files. All state changes stay inside `mktemp -d` temporary directories.

## Running the checks

```zsh
# From the repository root:
zsh -n plugins/ruby/ruby.plugin.zsh && python3 work/R14-T024/check.py
```
