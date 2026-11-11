# history plugin

Provides a couple of convenient aliases for using the `history` command to examine your command line history.

To use it, add `history` to the plugins array in your zshrc file:

```zsh
plugins=(... history)
```

## Aliases

| Alias | Command              | Description                                                      |
|-------|----------------------|------------------------------------------------------------------|
| `h`   | `history`            | Prints your command history                                      |
| `hl`  | `history \| less`    | Pipe history output to less to search and navigate it easily     |
| `hs`  | `history \| grep`    | Use grep to search your command history                          |
| `hsi` | `history \| grep -i` | Use grep to do a case-insensitive search of your command history |

## Example

This self-contained example seeds three history events, searches them with `hs`, and verifies with `h` that searching leaves the history list unchanged.

### Setup

<!-- history-example:setup:start -->
```zsh
print -s 'git status'
print -s 'ls -la'
print -s 'git commit -m "docs"'
```
<!-- history-example:setup:end -->

### Command

<!-- history-example:command:start -->
```zsh
hs git
```
<!-- history-example:command:end -->

### Output

<!-- history-example:output:start -->
```text
    1  git status
    3  git commit -m "docs"
```
<!-- history-example:output:end -->

### State verification

Running `h` afterwards confirms the history still contains all three events unchanged:

<!-- history-example:verify:start -->
```zsh
h
```
<!-- history-example:verify:end -->

<!-- history-example:verify-output:start -->
```text
    1  git status
    2  ls -la
    3  git commit -m "docs"
```
<!-- history-example:verify-output:end -->
