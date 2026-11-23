# R14-T026 — Implementation readability & characterization checks: `plugins/git-lfs`

**Student:** Keshav Gupta  
**Task:** R14-T026 · 6 of 10 (Issue #29)  
**Branch:** `student/e26b07f0722/R14-T026`

## What was done

### 1. Source simplification
In `plugins/git-lfs/git-lfs.plugin.zsh`, simplified the `gplfs` helper function from:
```zsh
function gplfs() {
  local b="$(git_current_branch)"
  git lfs push origin "$b" --all
}
```
to:
```zsh
function gplfs() {
  git lfs push origin "$(git_current_branch)" --all
}
```
This clarifies the single responsibility of `gplfs` by streaming the evaluated branch directly into `git lfs push`, removing the unnecessary intermediate local variable assignment while preserving 100% identical observable behavior.

### 2. Documentation improvement
Updated `plugins/git-lfs/README.md` to correct the function call signature to `$(git_current_branch)` and added an **Alias and Function Contracts** table.

### 3. Automated check (`work/R14-T026/check.py`)

| # | Type | Entry point | Assertion Details |
|---|------|-------------|-------------------|
| Syntax | pass | `git-lfs.plugin.zsh` | `zsh -n` exits 0 |
| Test 1 | success / state | Sourcing | Aliases `glfsi`, `glfst`, `glfsls`, and function `gplfs` defined; unrelated aliases untouched |
| Test 2 | success / options | `glfsi` (`git lfs install`) | Forwards option flags (`--skip-smudge`) to `git lfs install` intact |
| Test 3 | pattern quoting / wildcards | `glfst` (`git lfs track`) | Preserves quoted patterns with wildcards and spaces (`"*.psd"`, `"assets/3d models/*.obj"`) without word-splitting |
| Test 4 | success / listing | `glfsls` (`git lfs ls-files`) | Forwards listing options (`-s --all`) intact |
| Test 5 | simplified helper | `gplfs` | Resolves branch via `git_current_branch` and calls `git lfs push origin <branch> --all` |
| Test 6 | documented edge / failure | `glfsi` | Git command failure exit code (1) propagates cleanly |
| Test 7 | state isolation | Sandbox check | Isolated sandbox `FAKE_HOME != HOME`; user environment untouched |

All external commands (`git`) are replaced by shell stubs on an isolated temporary PATH. All state changes stay inside `mktemp -d` temporary directories.

## Running the checks

```zsh
# From the repository root:
zsh -n plugins/git-lfs/git-lfs.plugin.zsh && python3 work/R14-T026/check.py
```
