# Core

The `:Debug` command itself, the feature-flag system it dispatches through,
and the health check — the parts every category on the other pages relies on.

## One dispatcher, two-level completion

A single `:Debug {category} {action} [args]` user command replaces what used to
be a set of separate legacy commands. `commands.lua` builds a
category → action → handler registry lazily (leaf modules load on first use)
and drives both dispatch and completion from that same registry, so completion
cannot drift out of sync with what actually runs.

Completion is context-sensitive at every position and reflects the **active**
config, not the full feature set: `neotree` stays out of `:Debug <Tab>` until
`features.neotree = true` is set. `:Debug autocmds sources <Tab>` goes further
and completes its own keyword arguments, with `event=` completing against real
event names once typed far enough (`event=Buf<Tab>` → `event=BufAdd
event=BufEnter …`).

The `:Debug` command is built with
[`lib.nvim.bindings.usercmd.composer`](https://github.com/WKDSteve/lib.nvim).
Handle arguments use the composer's typed slots: `report win`,
`inspect buffer` and `inspect window` complete against live window/buffer ids,
and `keylogger start [file]` gets path completion (the file need not exist yet
— it is the directory part that needs typing out). That matters more than for a
typo-able name: a window id is unguessable, so without completion the only way
to supply one is to run `:echo win_getid()` first. `proc` and
`performance startup` deliberately keep the generic slot — this plugin does not
enumerate those values, so a completer would have nothing true to offer.

- **Module:** `commands.lua` (`M.dispatch`, `M.complete`, `build_registry`),
  `bindings/usercmds.lua` (registration, `HANDLE_ARG`)
- **Config:** `opts.command` (name of the registered command, default
  `"Debug"`)
- **Usercmds:** `:Debug {category} {action}` — see
  [BINDINGS.md](../BINDINGS.md#user-commands)

## Overview as a scrollable float

Running `:Debug` with no arguments renders a scrollable floating window listing
every enabled category and its actions. It falls back to a single notification
when a float cannot be opened (headless, no UI) — or permanently, when
configured to.

- **Module:** `commands.lua` (`overview`, `overview_float`), built on
  `lib.nvim.window.make_scratch`
- **Config:** `opts.overview` (`"float"` default, or `"notify"`)

## Per-category feature flags, with an `all = true` shorthand

Every category (`views`, `reports`, `autocmds`, `tools`, `terminals`,
`nvim_options`, `markdown`, `module_reload`, `neotree`, `filetree`, `neotest`,
`proc_trace`, `performance`) is gated by its own `features.*` boolean, checked by the
dispatcher before the category is reachable from completion at all. Passing
`{ all = true }` to `setup()` flips every flag on instead of listing each one.

- **Module:** `config/init.lua` (`M.setup`), `commands.lua` (`enabled`,
  `enabled_categories`)
- **Config:** `opts.features.*`, `opts.all` — see
  [configuration.md](../configuration.md)

## Immutable defaults, idempotent `setup()`

`config/DEFAULTS.lua` is the single source of truth for every default;
`config/init.lua` deep-merges user options over a fresh copy of it and exposes
the result via `get()`. `debugging.setup()` guards against running twice, so a
config that gets required and set up from more than one place stays safe.

- **Module:** `config/DEFAULTS.lua`, `config/init.lua` (`M.setup`, `M.get`),
  `init.lua` (`M.setup`)

## `:checkhealth debugging`

One `vim.health.start()` section per concern: the plugin's own load state,
every `lib.nvim` module it depends on, external tools (clipboard provider,
nvim-treesitter, noice.nvim for the views capture, which-key, gitsuite) and
write permissions for the state directory, the recent-messages popup in its own
section after the externals (message store, whether `ui.kit.message_log` makes
it live, whether the `ext_messages` logger is attached and, if not, why:
`renderer_override = false`, noice loaded but not running, `setup()` not
called, or no renderer at all), `vim.loader` for `module reload`, the Lua Tree-sitter parser for the
`autocmds sources` audit, `vim.v.progpath` for the startup benchmark, whether
the injectable Neo-tree bridge targets resolve, and the bundled watcher script
plus PowerShell availability for `proc watch`. A missing optional piece
therefore shows up as exactly the feature it degrades, not as a generic
warning.

- **Module:** `health.lua` (`M.check`)
- **Usercmds:** `:Debug health`, or `:checkhealth debugging` directly

## Built on lib.nvim as a deliberate shared dependency

Notifications, the scratch and float window helpers, buffer/window/tab report
utilities, filesystem writes, path normalization, the recursive directory
walker, the in-memory scan cache, the keymap registry, and the
`proc_trace` wrapper all come from
[`lib.nvim`](https://github.com/WKDSteve/lib.nvim) rather than being
hand-rolled per feature — the same modules the health check's "lib.nvim"
section verifies are present.

- **Module:** see [architecture.md](../architecture.md) for the full list of borrowed modules
