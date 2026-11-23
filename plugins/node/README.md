# node plugin

This plugin adds `node-docs` function that opens specific section in [Node.js](https://nodejs.org)
documentation (depending on the installed version).

To use it, add `node` to the plugins array of your zshrc file:

```zsh
plugins=(... node)
```

## Usage

```zsh
# Opens https://nodejs.org/docs/latest-v10.x/api/fs.html
$ node-docs fs
# Opens https://nodejs.org/docs/latest-v10.x/api/path.html
$ node-docs path
```

The section name is used exactly as typed, so quote it if it contains spaces or shell wildcards.
Without an argument, `node-docs` opens the page that lists all sections (`all.html`):

```zsh
# Opens https://nodejs.org/docs/latest-v10.x/api/all.html
$ node-docs
```
