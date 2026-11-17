# autopep8 plugin

This plugin adds completion for [autopep8](https://pypi.org/project/autopep8/), a tool that automatically formats Python code to conform to the [PEP 8](http://www.python.org/dev/peps/pep-0008/) style guide.

Short and long spellings of the same option share one completion definition. Each
spelling remains available with the same description and argument completion.

To use it, add autopep8 to the plugins array of your zshrc file:
```
plugins=(... autopep8)
```
