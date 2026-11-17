# JFrog CLI

This plugin provides completion for [JFrog CLI](https://github.com/jfrog/jfrog-cli).

JFrog CLI provides a simple interface that automates access to [Artifactory](https://jfrog.com/artifactory), [Xray](https://jfrog.com/xray), [Bintray](https://jfrog.com/bintray) and [Mission Control](https://jfrog.com/mission-control) through their respective REST APIs.

To use it, add `jfrog` to the plugins array in your zshrc file:

```zsh
plugins=(... jfrog)
```

## Running the Isolated Completion Check

Run `python3 work/R14-T009/check.py` from the repository root to syntax-check
the plugin and exercise its `jfrog` completion function. The check uses a
temporary Zsh configuration and a stub JFrog CLI, so it does not need access
to Artifactory, Xray, or another JFrog service. Its failure case verifies the
completion fallback when the CLI returns no suggestions. It checks the CLI's
status and the fallback's non-zero status; the Python entry point itself exits
non-zero if any fixture or syntax assertion fails.
