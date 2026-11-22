# Deno Plugin

This plugin sets up completion and aliases for [Deno](https://deno.land).

## Prerequisites

- `deno` must be on your `PATH`.
  - If `deno` is not found, the **aliases are still defined** (they are
    declared before the check) but the completion script is not loaded.
- The plugin respects `DENO_DIR` and `DENO_INSTALL_ROOT` if set; each shell
  session uses its own environment — these variables do not carry over between
  isolated sessions.

## Aliases

| Alias | Full command     | Description                                      |
| ----- | ---------------- | ------------------------------------------------ |
| dc    | deno compile     | Compile the given source file to a self-contained executable |
| dca   | deno cache       | Cache and compile remote dependencies            |
| dck   | deno check       | Type-check the given source file without running it |
| dfmt  | deno fmt         | Format source files                              |
| dh    | deno help        | Show help                                        |
| dli   | deno lint        | Lint source files                                |
| drn   | deno run         | Run a script                                     |
| drA   | deno run -A      | Run a script with all permissions                |
| drw   | deno run --watch | Run a script and restart on file changes         |
| dsv   | deno serve       | Run a server                                     |
| dts   | deno test        | Run tests                                        |
| dup   | deno upgrade     | Upgrade Deno to the latest version               |
