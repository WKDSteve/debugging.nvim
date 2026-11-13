![debugging-nvim](assets/icons/debugging-nvim/png/debugging-nvim-128.png)

> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# debugging.nvim

```
    ___      __                   _                       _
   / _ \___ / /  __ _____ ____ _(_)__  ___ _  ___ _   __(_)_ _
  / // / -_) _ \/ // / _ `/ _ `/ / _ \/ _ `/ / _ \ |/ / /  ' \
 /____/\__/_.__/\_,_/\_, /\_, /_/_//_/\_, (_)_//_/___/_/_/_/_/
                    /___//___/        /___/
        one :Debug command for every Neovim debugging tool
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/WKDSteve/debugging.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/WKDSteve/debugging.nvim/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)
[![wkd](https://img.shields.io/badge/wkd-family-c6ff3d)](https://wkdsteve.github.io/wkd/p/debugging/)

> Part of the [wkd](https://wkdsteve.github.io/wkd/) family — see this plugin's [page](https://wkdsteve.github.io/wkd/p/debugging/) on the site.

One `:Debug {category} {action}` command for every Neovim debugging tool.

Debugging tools accumulate as scattered one-off commands, each with a name you
have to remember before you can use it. This plugin puts all of them behind a
single dispatcher with two-level tab completion, so the surface is discoverable
rather than memorised.

---

## Documentation

Start at [docs/README.md](docs/README.md) — what's where, and which question
each page answers.

### The Basics

- [Requirements](docs/installation.md#requirements) — Neovim version, required and optional plugins.
- [Installation](docs/installation.md) — every plugin manager, and what lazy-loading costs.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

### Configuration

- [What you get with the defaults](docs/what-you-get.md) — the commands that matter on day one.
- [All options](docs/configuration.md) — every `setup()` option and its default.
- [Command reference](docs/commands.md) — every category and action, with completion behaviour.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap and user command in one table.

### The Rest

- [Features](docs/FEATURES/README.md) — what each group of `:Debug` categories does, and why it works that way.
- [Around it](docs/around-it.md) — how this plugin's scope differs from its siblings in the collection.
- [Workflow](docs/WORKFLOW.md) — which category to reach for when, and the gotchas in each.
- [Diagnosing UI freezes](docs/troubleshooting.md) — using `:Debug proc` to trace blocking calls and hung child processes.
- [Health check](docs/commands.md#health-check) — what `:checkhealth debugging` reports.
- [Architecture](docs/architecture.md) — module layout and the dispatcher's shape.
- [Contributing](docs/CONTRIBUTING.md) — ground rules and project layout.
- [Feedback](https://github.com/WKDSteve/debugging.nvim/issues) — bug reports, feature requests, and open-ended questions.

`:help debugging` is the same reference inside the editor.

---

## License

MIT — see [LICENSE](LICENSE).

<!-- connections:begin (written by the app-icons tool of the workshop; change integrations.json there, not this block) -->
## Connections

![debugging.nvim: what it uses and what uses it](assets/graphs/debugging.nvim.png)

**Uses**

- [gitsuite.nvim](https://github.com/WKDSteve/gitsuite.nvim): The reports of debugging.nvim ask gitsuite.nvim whether a buffer has merge conflicts (`gitsuite.features.conflict`). ([picture](assets/graphs/pair/debugging.nvim--gitsuite.nvim.png))
- [ui.nvim](https://github.com/WKDSteve/ui.nvim): The message popup of debugging.nvim is live and paginated with `ui.kit.message_log` of ui.nvim; without it the popup shows a static dump. ([picture](assets/graphs/pair/debugging.nvim--ui.nvim.png))
- [lib.nvim](https://github.com/WKDSteve/lib.nvim): the shared base of the plugins.
<!-- connections:end -->
