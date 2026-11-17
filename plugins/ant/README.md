# Ant

This plugin provides completion for [Ant](https://ant.apache.org/).

When the plugin is loaded, it sets `ANT_ARGS` to use Ant's color logger if
`ANT_ARGS` is unset or empty. A non-empty value that you set yourself is
preserved.

To use it, add `ant` to the plugins array in your zshrc file:

```zsh
plugins=(... ant)
```

It caches ant targets in a file named `.ant_targets`, you might want to add that to
your `.gitignore` file.
