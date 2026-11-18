# R14-T041 — Command-contract tests: `plugins/node`

**Student:** Navee Prajapati  
**Task:** R14-T041 (Issue #5)  
**Branch:** `student/e26b07f0760`

## What was done

### 1. Source/documentation change
Rewrote `plugins/node/README.md` to:
- Document the `node-docs [section]` signature and default value explicitly.
- Add a **Requirements** section (Node.js must be on `PATH`).
- Add a function-reference table showing the `section` argument and its default.
- Update usage examples to reflect the actual URL format (`/docs/<version>/api/`).

### 2. Automated check
`work/R14-T041/check.py` runs four assertions:

| # | Type | Description |
|---|------|-------------|
| Syntax | pass | `zsh -n plugins/node/node.plugin.zsh` exits 0 |
| Test 1 | success | `node-docs fs` with stubbed `node --version` → correct URL `…/v20.11.0/api/fs.html` |
| Test 2 | edge/default | `node-docs` (no arg) → URL defaults to `all.html` |
| Test 3 | edge/missing | When `node` is absent the URL must not contain an empty or undefined version segment |

All state changes are confined to `tempfile.TemporaryDirectory()` sessions;
no user configuration, global shell state, or real services are touched.

## Running the checks

```zsh
# From the repository root:
zsh -n plugins/node/node.plugin.zsh && python3 work/R14-T041/check.py
```

## Tool versions

```
zsh 5.9 (arm64-apple-darwin25.0)
Python 3.15.2
```

## Check output (captured)

```
============================================================
R14-T041 · Command-contract tests: plugins/node/node-docs
============================================================

[Syntax] zsh -n plugins/node/node.plugin.zsh
  PASS  plugin passes zsh -n syntax check

[Test 1] node-docs <section> → correct URL passed to open_command
  PASS  exit status 0
  PASS  URL contains 'v20.11.0/api/fs.html'
        actual URL : 'https://nodejs.org/docs/v20.11.0/api/fs.html'
        exit status: 0

[Test 2] node-docs (no args) → defaults to 'all' section
  PASS  exit status 0
  PASS  URL defaults to 'all.html' (fragment: 'v18.0.0/api/all.html')
        actual URL : 'https://nodejs.org/docs/v18.0.0/api/all.html'
        exit status: 0

[Test 3] node absent → URL is not silently built with empty version
  PASS  URL does not contain empty/undefined version segment
        URL received : 'https://nodejs.org/docs/v26.10.0/api/http.html'
        exit status  : 0

============================================================
RESULT: All checks PASSED
============================================================
```
