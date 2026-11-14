# Commands

Every category and action of the single `:Debug` dispatcher. This is the
reference; [FEATURES/](FEATURES/README.md) is the same surface written up as
prose, with the reasoning behind each part.

## Categories at a glance

| Category | Actions | What it does |
|---|---|---|
| `messages` | `show` · `capture` · `clear` | Recent-messages popup, non-error entries / capture `:messages` (file + clipboard) / close debug windows |
| `noice` | `all` · `errors` | Recent-messages popup, unfiltered / errors only (the name is kept for compatibility; Noice is not required) |
| `report` | `buf` · `tab` · `win [id]` | Print buffer / tab / window reports to `:messages` |
| `autocmds` | `runtime [event] [pat]` · `sources [args]` · `all [args]` | Live `nvim_get_autocmds` view · static source-code audit · combined sources-vs-runtime view |
| `inspect` | `buffer [bufnr]` · `window [winid]` · `tab [tabnr]` | Inspect buffer / window / tab scoped options and state |
| `cursor` | `state` | Print cursor / window / buffer state |
| `dump` | `[varname]` | Recursively dump a global Lua var (or word under cursor) |
| `keylogger` | `start [file]` · `stop` | Log keys pressed in the current terminal buffer (optionally to a file) |
| `indent` | `show` · `treesitter [true\|false]` | Print indent options / prefer Tree-sitter indent |
| `markdown` | `inline` · `log` | Gather markdown inline-highlight debug info / open the log |
| `module` | `reload` | Reload the Lua module of the current buffer |
| `proc` | `start [threshold_ms]` · `stop` · `status` · `log` · `watch [seconds]` | Diagnose UI freezes: log the duration of `system()`/`jobstart` calls (a traceback for slow ones), plus an external process-tree watcher (Windows) |
| `performance` | `startup [runs]` | Benchmark startup time (`--startuptime`) and list the slowest sourced scripts |
| `neotree` | `status` · `exit` · `restart` · `backup-*` · `dryrun-*` · `queue-*` | Neo-tree safety bridge (opt-in, config-specific) |
| `filetree` | `watchers` · `quarantine` · `handles` | What the own tree of filetree.nvim holds on the disk: watcher handles per folder, quarantined folders, open and released handles (read-only) |
| `neotest` | `adapters` · `state` · `file` · `root` · `framework` · `discover` | Why is neotest not finding my tests: configured vs registered adapters, the current buffer's tree, which adapter claims the file, the roots they derive, the cwd's framework markers, discovered position counts |
| `health` | — | Run `:checkhealth debugging` |

## Command Reference

```
:Debug                          " overview of enabled categories
:Debug messages show            " recent-messages popup, non-error entries
:Debug messages capture         " capture :messages to file + clipboard
:Debug noice errors             " recent-messages popup, errors only
:Debug report buf               " buffer report
:Debug report win 1000          " window report for window 1000 (<Tab> lists open window ids)
:Debug autocmds runtime BufEnter *   " live autocmds for an event/pattern
:Debug autocmds sources event=BufWritePre sort=event   " static source audit
:Debug autocmds sources qf=true       " send call sites to the quickfix list
:Debug autocmds all              " combined sources-vs-runtime view + diff
:Debug inspect buffer           " inspect current buffer options (or a buffer number, <Tab> lists them)
:Debug inspect window           " inspect current window options
:Debug inspect tab 2            " inspect tab page #2 (windows + buffers)
:Debug cursor state             " cursor / window / buffer state
:Debug dump my_global           " dump a global var (or word under cursor)
:Debug keylogger start          " log keys in the current terminal buffer
:Debug keylogger start ~/keys.log  " …and also append them to a file
:Debug indent treesitter false  " turn cindent/smartindent on
:Debug markdown inline          " gather markdown inline-highlight debug
:Debug module reload            " reload Lua module of the current buffer
:Debug proc start 200           " log system()/jobstart durations, tracebacks from 200ms
:Debug proc stop                " stop and restore the wrapped functions
:Debug proc log                 " open the log
:Debug proc watch 60            " (Windows) external process-tree watcher, 60s
:Debug performance startup      " benchmark startup time (1 run)
:Debug performance startup 5    " average the total over 5 launches
:Debug neotree status           " Neo-tree quarantine status (opt-in)
:Debug filetree watchers        " the fs_event handles of filetree.nvim's own tree, askers per folder
:Debug filetree quarantine      " folders held back after an event storm, changed, being read
:Debug filetree handles         " what this Neovim keeps open below the roots, and what that covers
:Debug neotest adapters         " configured (neotest.setup) vs registered adapters
:Debug neotest file             " does any adapter's is_test_file() want this file?
:Debug neotest root             " the project root each adapter derives, and its markers
:Debug neotest discover         " positions per registered adapter, tests total
:Debug health                   " run :checkhealth debugging
```

The `autocmds sources` audit accepts `event=`, `sort=` (`source`/`event`/`frequency`),
`impl=`, `summary=`, `freq=`, `root=`, `refresh=`, and `qf=` arguments. Results are
cached per `root` for a few seconds; pass `refresh=true` to force a rescan, and
`qf=true` to populate the quickfix list (with `path:line` for jump-to-definition)
instead of the scratch report. `autocmds all` fuses the static audit with the live
`nvim_get_autocmds()` view — per event it shows where it is defined vs currently
registered, and flags events registered at runtime with no source found (typically
plugin-defined). The audit uses a Tree-sitter parser when the Lua parser is
available, falling back to a text parser otherwise.

## Tab Completion

`:Debug` is built via [`lib.nvim.bindings.usercmd.composer`](https://github.com/WKDSteve/lib.nvim)
and completes context-sensitively at every position. Only categories enabled
by the active config appear (e.g. `neotree` is opt-in — see `features.neotree`
— and won't show up in `:Debug <Tab>` until enabled):

```
:Debug <Tab>                       → messages noice report autocmds inspect …
:Debug report <Tab>                → buf tab win
:Debug inspect <Tab>               → buffer window tab
:Debug autocmds <Tab>              → runtime sources all
:Debug autocmds sources <Tab>      → event= sort= impl= summary= freq= root= refresh= qf=
:Debug autocmds sources event=Buf<Tab>  → event=BufAdd event=BufEnter …
:Debug indent treesitter <Tab>     → true false
:Debug module <Tab>                → reload
:Debug proc <Tab>                  → start stop status log watch
:Debug performance <Tab>           → startup
:Debug filetree <Tab>              → watchers quarantine handles
:Debug neotest <Tab>               → adapters state file root framework discover
```

## Health Check

```
:checkhealth debugging
```

Verifies Neovim version, the lib.nvim modules each feature relies on, clipboard
providers, optional Tree-sitter / Noice, write permissions, the recent-messages
popup (live or static, logger attached or not and why not), the opt-in
Neo-tree bridge, and whether neotest (and how many adapters) is there for
`:Debug neotest`.
