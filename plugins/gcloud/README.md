# gcloud

This plugin provides completion support for the
[Google Cloud SDK CLI](https://cloud.google.com/sdk/gcloud/).

To use it, add `gcloud` to the plugins array in your zshrc file.

```zsh
plugins=(... gcloud)
```

It relies on you having installed the SDK using one of the supported options
listed [here](https://cloud.google.com/sdk/install).

## Plugin Options

* Set `CLOUDSDK_HOME` in your `zshrc` file before you load oh-my-zsh if you have
your GCloud SDK installed in a non-standard location. The plugin will use this
as the base for your SDK if it finds it set already.

* If you do not have a `python2` in your `PATH` you'll also need to set the
`CLOUDSDK_PYTHON` environment variable at the end of your `.zshrc`. This is
used by the SDK to call a compatible interpreter when you run one of the
SDK commands.

## Testing

The plugin includes an isolated native test suite and automated regression verification harness:

- **Native Test Suite**:
  ```zsh
  zsh -df plugins/gcloud/tests/gcloud.test.zsh
  ```
  Runs 10 focused tests under an isolated `ZDOTDIR` with stubbed Google Cloud SDK fixtures, asserting auto-discovery, custom `CLOUDSDK_HOME` preservation, `path.zsh.inc` execution, completion loading, argument preservation with spaces, exit code propagation, and protected condition regressions.

- **Automated Regression Verification Harness**:
  ```zsh
  python3 work/R14-T060/check.py
  ```
  Runs the end-to-end regression mutation workflow: executes tests against original implementation (Scenario A), applies a temporary one-condition mutant inverting the `path.zsh.inc` guard (Scenario B) and verifies rejection, then restores the original implementation and re-tests (Scenario C).
