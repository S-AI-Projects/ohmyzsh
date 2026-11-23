# R14-T025 — Environment isolation checks: `plugins/mvn`

**Student:** Keshav Gupta  
**Task:** R14-T025 · 5 of 10 (Issue #28)  
**Branch:** `student/e26b07f0722/R14-T025`

## What was done

### 1. Source/documentation change
Updated `plugins/mvn/README.md` with a **Maven Wrapper Lookup & Environment Isolation** section documenting the deterministic wrapper lookup process, fallback behavior, missing-dependency handling, and argument forwarding guarantees for `mvn`, `mvnag`, and `mvnboot`.

### 2. Automated check (`work/R14-T025/check.py`)

| # | Type | Entry point | Assertion Details |
|---|------|-------------|-------------------|
| Syntax | pass | `mvn.plugin.zsh` | `zsh -n` exits 0 |
| Test 1 | success / state | Sourcing | Aliases `mvn`, `mvnag`, `mvnboot` defined; unrelated aliases untouched |
| Test 2 | success / wrapper | `mvnboot` | Resolves executable `mvnw` in parent directory; forwards `spring-boot:run` and quoted arguments; logs wrapper notice to stderr |
| Test 3 | success / fallback | `mvnag` | Without wrapper, falls back to `command mvn` with `archetype:generate` and arguments; empty stderr |
| Test 4 | edge / non-executable | `mvn` | Non-executable `mvnw` (mode 0644) is skipped and falls back to `mvn` |
| Test 5 | documented edge / failure | `mvnboot` | Wrapper non-zero exit status (3) propagates through unchanged |
| Test 6 | missing dependency | `mvn` | Missing `mvn` on `$PATH` when no wrapper exists exits with code 127 (`command not found`) while preserving shell state |
| Test 7 | state isolation | Sandbox check | Isolated sandbox `FAKE_HOME != HOME`; user environment untouched |

All external commands (`mvn`, `mvnw`) are replaced by shell stubs on isolated temporary PATHs. All state changes stay inside `mktemp -d` temporary directories.

## Running the checks

```zsh
# From the repository root:
zsh -n plugins/mvn/mvn.plugin.zsh && python3 work/R14-T025/check.py
```
