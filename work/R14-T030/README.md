# R14-T030 · conda Plugin Regression and Mutation Rejection Testing

## Overview

- **Item**: `conda`
- **Plugin Path**: `plugins/conda/conda.plugin.zsh`
- **Documentation**: `plugins/conda/README.md`
- **Task Type**: Regression Mutation & Argument Preservation
- **Assigned Branch**: `student/e26b07f0722/R14-T030`

## Actual Entry Points

| Alias | Target Command | Description |
|---|---|---|
| `cna` | `conda activate` | Activate a specified conda environment |
| `cnab` | `conda activate base` | Activate the base conda environment |
| `cncf` | `conda env create -f` | Create a new conda environment from an environment file |

## Scoped Improvements & Documentation Fix

1. **Documentation Correction (`plugins/conda/README.md`)**:
   - Fixed `-all` typo to `--all` for aliases `cnrn` (`conda remove -y --all -n`) and `cnrp` (`conda remove -y --all -p`).
   - Added documentation detailing the regression and mutation coverage for key entry points.

2. **Regression Assertions and Mutation Rejection**:
   - Tested entry point `cna` with arbitrary environment argument forwarding.
   - Tested regression invariant for `cnab` preserving the `base` environment parameter.
   - Tested regression invariant for `cncf` preserving the `env` sub-command and `-f` flag.
   - Introduced and evaluated temporary condition mutants:
     - Mutant 1: `cnab='conda activate'` (missing `base`). Rejection verified.
     - Mutant 2: `cncf='conda create -f'` (missing `env`). Rejection verified.

## Test Matrix

| # | Test Name | Exit Code | Description |
|---|---|:---:|---|
| 1 | `sourcing_state_transition` | 0 | Verifies all conda aliases are defined upon sourcing and unrelated aliases are intact |
| 2 | `cna_activate_environment` | 0 | Verifies `cna <env>` forwards `activate <env>` to conda |
| 3 | `cnab_activate_base_regression` | 0 | Asserts `cnab` forwards `activate base` |
| 4 | `cncf_env_create_regression` | 0 | Asserts `cncf <file>` forwards `env create -f <file>` |
| 5 | `mutation_rejection_cnab_dropped_base` | 0 | Verifies condition mutant dropping `base` is detected and killed by assertion |
| 6 | `mutation_rejection_cncf_dropped_env` | 0 | Verifies condition mutant dropping `env` subcommand is detected and killed by assertion |
| 7 | `documented_failure_invalid_flag` | 2 | Confirms unrecognized flags trigger failure status in stub |
| 8 | `sandbox_state_isolation` | 0 | Ensures isolated temporary directories do not leak into host environment |

## Running the Checks

From the repository root:
```zsh
zsh -n plugins/conda/conda.plugin.zsh && python3 work/R14-T030/check.py
```
