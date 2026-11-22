# R14-T047 · Executable command documentation tests: `plugins/conda`

**Student:** Navee Prajapati  
**Task:** R14-T047 (Issue #48)  
**Branch:** `student/e26b07f0760/R14-T047`

## What was done

### 1. Source / documentation change
Added a tested **Usage** section to `plugins/conda/README.md` providing a complete usage workflow with setup (`environment.yml`), command execution (`cncf`, `cna`, `cnab`), expected output, and environment state verification (`$CONDA_DEFAULT_ENV`). Also corrected the option spelling (`--all`) in the alias table.

### 2. Automated check (`work/R14-T047/check.py`)

| # | Type | Entry point | Assertion |
|---|------|-------------|-----------|
| Syntax | pass | — | `zsh -n plugins/conda/conda.plugin.zsh` exits 0 |
| Test 1 | success | `cncf` | Expands to `conda env create -f environment.yml` and exits 0 |
| Test 2 | success | `cna` | Expands to `conda activate my-project` and updates environment state to `my-project` |
| Test 3 | success | `cnab` | Expands to `conda activate base` and updates environment state to `base` |
| Test 4 | failure | `cncf` | Missing environment spec file returns non-zero exit code (1) and error on stderr |
| Test 5 | doc-workflow | all | Executes complete README usage example end-to-end, asserting setup, command output, and state |

All external conda commands are stubbed on a temporary `PATH`. All state transitions remain isolated inside `tempfile.TemporaryDirectory()` sessions. No real conda installation or global configuration is modified.

## Running the checks

```zsh
zsh -n plugins/conda/conda.plugin.zsh && python3 work/R14-T047/check.py
```

## Tool versions

```
zsh 5.9 (arm64-apple-darwin25.0)
Python 3.15.2
```

## Check output (captured)

```
============================================================
R14-T047 · Executable documentation tests: plugins/conda
Entry points: cncf, cna, cnab
============================================================

[Syntax] zsh -n plugins/conda/conda.plugin.zsh
  PASS  plugin passes zsh -n syntax check

[Test 1] SUCCESS - cncf creates environment from YAML file
  PASS  exit status 0
  PASS  arguments match ['env', 'create', '-f', 'environment.yml']
  PASS  output confirms creation
        conda argv : ['env', 'create', '-f', 'environment.yml']
        stdout     : Successfully created environment from environment.yml

[Test 2] SUCCESS - cna activates specified conda environment
  PASS  exit status 0
  PASS  arguments match ['activate', 'my-project']
  PASS  CONDA_DEFAULT_ENV state updated to 'my-project'
        conda argv : ['activate', 'my-project']
        env state  : my-project ✓

[Test 3] SUCCESS - cnab activates base environment
  PASS  exit status 0
  PASS  arguments match ['activate', 'base']
  PASS  CONDA_DEFAULT_ENV state updated to 'base'
        conda argv : ['activate', 'base']
        env state  : base ✓

[Test 4] FAILURE - cncf fails when environment file does not exist
  PASS  stderr reports missing file
  PASS  reported exit status is non-zero (1)
        stderr msg : Environment file not found
        exit code  : 1 ✓

[Test 5] DOC-WORKFLOW - executes complete README usage example
  PASS  create step completed with code 0
  PASS  environment activated as ml-env
  PASS  environment switched back to base
        setup      : environment.yml created ✓
        cncf run   : environment created ✓
        cna run    : ml-env active ✓
        cnab run   : base active ✓

============================================================
RESULT: All checks PASSED
============================================================
```
