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

## Troubleshooting

### Failing Invocation: Non-existent or Invalid `CLOUDSDK_HOME`

If `CLOUDSDK_HOME` is set in your `~/.zshrc` to an invalid or non-existent path:

```zsh
export CLOUDSDK_HOME="/nonexistent/google-cloud-sdk"
```

The plugin validates that `CLOUDSDK_HOME` exists. When pointing to an invalid directory, sourcing the plugin will report a diagnostic error and return exit status `1`:

```
[oh-my-zsh] gcloud: CLOUDSDK_HOME '/nonexistent/google-cloud-sdk' directory not found
```

Additionally, because `path.zsh.inc` and `completion.zsh.inc` cannot be loaded, subsequent attempts to invoke `gcloud` fail with:

```
zsh: command not found: gcloud
```
Exit status: `127`.

### Corrected Invocation

Ensure `CLOUDSDK_HOME` points to your actual Google Cloud SDK installation directory containing `path.zsh.inc` and `completion.zsh.inc`:

```zsh
export CLOUDSDK_HOME="$HOME/google-cloud-sdk"
```

When properly configured, sourcing the plugin automatically updates `$PATH` and enables completion for `gcloud`. You can verify that the command succeeds:

```zsh
which gcloud
# Output: /path/to/google-cloud-sdk/bin/gcloud
gcloud --version
# Output: Google Cloud SDK ...
echo $?
# Output: 0
```

## Testing

The plugin includes an isolated automated test suite covering initialization, completion loading, diagnostic failure reporting, and corrected invocations:

```zsh
zsh -df plugins/gcloud/tests/gcloud.test.zsh
```
