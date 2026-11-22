# autopep8 plugin

This plugin adds completion for [autopep8](https://pypi.org/project/autopep8/), a tool that automatically formats Python code to conform to the [PEP 8](http://www.python.org/dev/peps/pep-0008/) style guide.

To use it, add autopep8 to the plugins array of your zshrc file:
```zsh
plugins=(... autopep8)
```

## Usage Example

### 1. Prerequisites and Setup

1. Install `autopep8` using `pip`:
   ```sh
   pip install autopep8
   ```
2. Enable the plugin in your `~/.zshrc`:
   ```zsh
   plugins=(... autopep8)
   ```
3. Reload your zsh configuration:
   ```zsh
   source ~/.zshrc
   ```

### 2. Command

To preview formatting changes as a unified diff without modifying the source file:

```sh
autopep8 --diff example.py
```

To format a Python file in place conforming to PEP 8 standards:

```sh
autopep8 --in-place --aggressive example.py
```

### 3. Expected Output

Running `autopep8 --diff example.py` on an unformatted file displays a unified diff:

```diff
--- original/example.py
+++ fixed/example.py
@@ -1,2 +1,2 @@
-def foo( x ):
-    return x+1
+def foo(x):
+    return x + 1
```

Running `autopep8 --in-place --aggressive example.py` formats the target file directly and exits with status code `0`.

### 4. State Verification

After in-place formatting, verify that the file now conforms to PEP 8 by running the diff command:

```sh
autopep8 --diff example.py
```

When the file conforms to PEP 8, the command outputs nothing and exits with code `0`. You can verify the exit status:

```zsh
echo $?
# Output: 0
```

### 5. Completion Verification

To verify that the autopep8 completion definition is loaded in your shell:

```zsh
print -r -- $_comps[autopep8]
# Output: _autopep8
```

## Testing

The plugin includes an isolated automated test suite covering initialization, completion registration, argument boundary preservation, and the documented usage example:

```zsh
zsh -df plugins/autopep8/tests/autopep8.test.zsh
```
