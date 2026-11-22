# R14-T023 — State-transition checks: `plugins/bundler`

**Student:** Keshav Gupta  
**Task:** R14-T023 · 3 of 10 (Issue #26)  
**Branch:** `student/e26b07f0722/R14-T023`

## What was done

### 1. Source/documentation change
Updated `plugins/bundler/README.md` with an **Alias Argument Contract & State Transitions** section documenting the state transitions and argument forwarding guarantees for `ba`, `bck`, and `bcn`.

### 2. Automated check (`work/R14-T023/check.py`)

| # | Type | Entry point | Before state | After state / assertion |
|---|------|-------------|--------------|-------------------------|
| Syntax | pass | `bundler.plugin.zsh` | — | `zsh -n` exits 0 |
| Test 1 | success / state transition | Plugin sourcing | `ba`, `bck`, `bcn` absent; `unrelated_alias` present | `ba='bundle add'` defined; `unrelated_alias` unchanged |
| Test 2 | ordinary success / unrelated | `ba` (`bundle add`) | Unrelated file and env var recorded | argv = `['add', 'rake', '--group', 'test']`; file & env var unchanged; exit 0 |
| Test 3 | ordinary success | `bck` (`bundle check`) | Clean stub state | argv = `['check', '--path', 'vendor/bundle']`; exit 0 |
| Test 4 | ordinary success | `bcn` (`bundle clean`) | Clean stub state | argv = `['clean', '--force']`; exit 0 |
| Test 5 | documented edge / failure | `bck` | Stub exit 1 (unsatisfied dependencies) | exit status 1; error reported; shell continues safely |
| Test 6 | documented edge / failure | `ba` | Stub exit 2 (invocation failure) | exit status 2 properly propagated to caller |
| Test 7 | state transition | `_within-bundled-project` | Empty directory without Gemfile | returns 1; after `touch Gemfile`, returns 0 |
| Test 8 | state isolation | Sandbox check | Real `HOME` recorded | Isolated sandbox `FAKE_HOME != HOME`; user state unmodified |

All external commands (`bundle`) are replaced by shell stubs on an isolated temporary PATH. All state changes stay inside `mktemp -d` temporary directories. No user or global configuration is modified.

## Running the checks

```zsh
# From the repository root:
zsh -n plugins/bundler/bundler.plugin.zsh && python3 work/R14-T023/check.py
```
