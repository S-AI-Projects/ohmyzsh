# R14-T043 — State-transition checks: `plugins/kubectl`

**Student:** Navee Prajapati  
**Task:** R14-T043 (Issue #44)  
**Branch:** `student/e26b07f0760/R14-T043`

## What was done

### 1. Source/documentation change
Added an **Alias argument contract** section to `plugins/kubectl/README.md`
documenting the precise state transitions, argument forwarding guarantees, and
side-effects for `kca`, `kaf`, and `kapk`.

### 2. Automated check (`work/R14-T043/check.py`)

| # | Type | Entry point | Before state | After state / assertion |
|---|------|-------------|--------------|-------------------------|
| Syntax | pass | — | — | `zsh -n` exits 0 |
| Test 1 | success | `kca` | `_kca` absent | argv = `[..., --all-namespaces]`; `_kca` unset; exit 0 |
| Test 2 | edge/multi-arg | `kca` | — | all original args preserved; `--all-namespaces` last |
| Test 3 | success | `kaf` | — | argv = `['apply', '-f', 'deployment.yaml']`; exit 0 |
| Test 4 | success | `kapk` | — | argv = `['apply', '-k', './overlays/prod']`; exit 0 |
| Test 5 | boundary/unrelated | `k` alias | `k=kubectl` | unchanged after `kca` call |

All external commands (`kubectl`, `aws_completer`, etc.) are replaced by shell
stubs on a temporary PATH. All state changes are isolated inside
`tempfile.TemporaryDirectory()` sessions. No real Kubernetes cluster, kubectl
binary, or user configuration is modified.

## Running the checks

```zsh
# From the repository root:
zsh -n plugins/kubectl/kubectl.plugin.zsh && python3 work/R14-T043/check.py
```

## Tool versions

```
zsh 5.9 (arm64-apple-darwin25.0)
Python 3.15.2
```

## Check output (captured)

```
============================================================
R14-T043 · State-transition checks: plugins/kubectl
Entry points: kca (_kca), kaf, kapk
============================================================

[Syntax] zsh -n plugins/kubectl/kubectl.plugin.zsh
  PASS  plugin passes zsh -n syntax check

[Test 1] kca — appends --all-namespaces; _kca unset after call
  PASS  exit status 0
  PASS  BEFORE: _kca function did not exist (clean state)
  PASS  AFTER:  _kca unset itself (state transition complete)
  PASS  argv[0] == 'get'
  PASS  argv[1] == 'pods'
  PASS  last arg == '--all-namespaces'
        before state : _kca absent ✓
        kubectl argv : ['get', 'pods', '--all-namespaces']
        after  state : _kca absent ✓
        exit status  : 0

[Test 2] kca EDGE — multi-arg call; all args forwarded + --all-namespaces last
  PASS  exit status 0
  PASS  arg '-n' preserved
  PASS  arg 'default' preserved
  PASS  last arg == '--all-namespaces'
        kubectl argv : ['get', 'pods', '-n', 'default', '--all-namespaces']
        exit status  : 0

[Test 3] kaf — kubectl apply -f <file>; exit 0
  PASS  exit status 0
  PASS  argv == ['apply', '-f', 'deployment.yaml']
        kubectl argv : ['apply', '-f', 'deployment.yaml']
        exit status  : 0

[Test 4] kapk — kubectl apply -k <dir>; exit 0
  PASS  exit status 0
  PASS  argv == ['apply', '-k', './overlays/prod']
        kubectl argv : ['apply', '-k', './overlays/prod']
        exit status  : 0

[Test 5] BOUNDARY — alias k=kubectl unchanged after kca is called
  PASS  exit status 0
  PASS  alias k unchanged after kca call
        k alias before : k_before:k=kubectl
        k alias after  : unchanged
        exit status    : 0

============================================================
RESULT: All checks PASSED
============================================================
```
