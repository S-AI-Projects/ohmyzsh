# R14-T042 — Argument-boundary tests: `plugins/aws`

**Student:** Navee Prajapati  
**Task:** R14-T042 (Issue #43)  
**Branch:** `student/e26b07f0760/R14-T042`

## What was done

### 1. Source/documentation change
Added an **Argument contract** section to `plugins/aws/README.md` documenting
the precise argument boundaries and exit-status guarantees for `agp`, `agr`,
and `_aws_update_state`.

### 2. Automated check (`work/R14-T042/check.py`)

| # | Type | Entry point | Assertion |
|---|------|-------------|-----------|
| Syntax | pass | — | `zsh -n plugins/aws/aws.plugin.zsh` exits 0 |
| Test 1 | success | `agp` | `AWS_PROFILE=my-dev-profile` → prints `my-dev-profile`; exit 0 |
| Test 2 | success | `agr` | `AWS_REGION=us-east-1` → prints `us-east-1`; exit 0 |
| Test 3 | edge/empty | `agp` | `AWS_PROFILE` unset → empty output; exit 0 |
| Test 4 | edge/empty | `agr` | `AWS_REGION` unset → empty output; exit 0 |
| Test 5 | boundary/fail | `_aws_update_state` | state enabled, parent dir missing → exit 1; file not created |
| Test 6 | boundary/noop | `_aws_update_state` | state disabled → exit 0; file not written |

All state changes are confined to `tempfile.TemporaryDirectory()` sessions;
no real AWS credentials, services, or user configuration are touched.

## Running the checks

```zsh
# From the repository root:
zsh -n plugins/aws/aws.plugin.zsh && python3 work/R14-T042/check.py
```

## Tool versions

```
zsh 5.9 (arm64-apple-darwin25.0)
Python 3.15.2
```

## Check output (captured)

```
============================================================
R14-T042 · Argument-boundary tests: plugins/aws
Entry points: agp, agr, _aws_update_state
============================================================

[Syntax] zsh -n plugins/aws/aws.plugin.zsh
  PASS  plugin passes zsh -n syntax check

[Test 1] agp — AWS_PROFILE set → prints profile name; exit 0
  PASS  exit status 0
  PASS  output is profile name 'my-dev-profile'
        args       : AWS_PROFILE=my-dev-profile  (no positional args)
        output     : 'my-dev-profile'
        exit status: 0

[Test 2] agr — AWS_REGION set → prints region; exit 0
  PASS  exit status 0
  PASS  output is region 'us-east-1'
        args       : AWS_REGION=us-east-1  (no positional args)
        output     : 'us-east-1'
        exit status: 0

[Test 3] agp EDGE — AWS_PROFILE unset → empty output; exit 0
  PASS  exit status 0
  PASS  output is empty (no profile set)
        args       : (AWS_PROFILE unset, no positional args)
        output     : ''
        exit status: 0

[Test 4] agr EDGE — AWS_REGION unset → empty output; exit 0
  PASS  exit status 0
  PASS  output is empty (no region set)
        args       : (AWS_REGION unset, no positional args)
        output     : ''
        exit status: 0

[Test 5] _aws_update_state BOUNDARY — state enabled, missing dir → exit 1
  PASS  _aws_update_state returns exit 1 when parent dir missing
  PASS  state file was NOT created (dir missing)
        inner exit     : 1
        file exists    : False

[Test 6] _aws_update_state BOUNDARY — state disabled → no-op; exit 0
  PASS  _aws_update_state exit 0 when disabled
  PASS  state file not written when disabled
        AWS_PROFILE_STATE_ENABLED : false
        inner exit                : 0
        file created              : False

============================================================
RESULT: All checks PASSED
============================================================
```
