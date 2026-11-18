# node plugin

This plugin adds the `node-docs` function that opens a specific section of the
[Node.js](https://nodejs.org) API documentation for the **currently installed**
Node.js version.

To use it, add `node` to the plugins array in your `.zshrc`:

```zsh
plugins=(... node)
```

## Requirements

- `node` must be on your `PATH` (the installed version is used to build the URL).

## Functions

### `node-docs [section]`

Opens `https://nodejs.org/docs/<version>/api/<section>.html` in the default
browser using `open_command`.

| Argument  | Default | Description                              |
| --------- | ------- | ---------------------------------------- |
| `section` | `all`   | API section name, e.g. `fs`, `path`, `http` |

When called with no argument the **complete API index** (`all.html`) is opened.

## Usage

```zsh
# Opens the full API index for the installed Node.js version
$ node-docs

# Opens the 'fs' section  (e.g. https://nodejs.org/docs/v20.11.0/api/fs.html)
$ node-docs fs

# Opens the 'path' section
$ node-docs path

# Opens the 'http' section
$ node-docs http
```
