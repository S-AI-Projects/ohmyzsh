# R14-T027 — Tested usage example & initialization checks: `plugins/asdf`

**Student:** Keshav Gupta  
**Task:** R14-T027 · 7 of 10 (Issue #30)  
**Branch:** `student/e26b07f0722/R14-T027`

## What was done

### 1. Source/documentation change
Updated `plugins/asdf/README.md` with a **Verified Usage Example** section containing complete setup instructions, command invocations, expected command outputs, and state verification steps (shims in `$PATH` and `.tool-versions` inspection).

### 2. Automated check (`work/R14-T027/check.py`)

| # | Type | Entry point | Assertion Details |
|---|------|-------------|-------------------|
| Syntax | pass | `asdf.plugin.zsh` | `zsh -n` exits 0 |
| Test 1 | success / initialization | Plugin sourcing | Sets `ASDF_DATA_DIR=$HOME/.asdf`, prepends shims to `$PATH`, binds `_comps[asdf]=_asdf`; preserves unrelated env vars |
| Test 2 | verified usage example | `asdf` CLI workflow | Executes the documented README workflow (`asdf plugin add`, `asdf install`, `asdf set`, `asdf current`); asserts outputs match documented text and state changes persist in `.tool-versions` |
| Test 3 | documented failure / edge | Missing dependency | When `asdf` is not on `$PATH`, returns cleanly without setting `ASDF_DATA_DIR`, modifying `$PATH`, or binding completions |
| Test 4 | success / custom config | `ASDF_DATA_DIR` | User-defined custom `ASDF_DATA_DIR` is preserved and its shims directory is prepended |
| Test 5 | path deduplication | `shims` in `$PATH` | If shims is already in `$PATH`, sourcing the plugin places it at the front without duplicate entries |
| Test 6 | state isolation | Sandbox check | Isolated sandbox `FAKE_HOME != HOME`; user environment untouched |

All external commands (`asdf`) are replaced by shell stubs on an isolated temporary PATH. All state changes stay inside `mktemp -d` temporary directories.

## Running the checks

```zsh
# From the repository root:
zsh -n plugins/asdf/asdf.plugin.zsh && python3 work/R14-T027/check.py
```
