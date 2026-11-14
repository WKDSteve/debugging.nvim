# debugging.nvim — Binding Cheatsheet

Every keymap and user command `debugging.nvim` defines. Kept in
sync with:

- keymaps  — `lua/debugging/bindings/keymaps.lua`
- commands — `lua/debugging/bindings/usercmds.lua` (registration) + `lua/debugging/commands.lua` (dispatch/completion logic)

## Default Keymaps

Normal-mode keymaps installed by `bindings.setup()`, gated by
`config.views.keymaps.enable`. The prefix defaults to `<lt>`, i.e. the
literal `<` key.

Each key is individually overridable by its action name — the names in the
table below — so moving one does not mean moving all seven. See
[configuration.md](configuration.md#views-keymaps).

| lhs | mode | action | desc |
| --- | --- | --- | --- |
| `<lt>m` | n | `messages` | Recent messages, non-error (`views.recent`, live + paginated when ui.nvim is installed) |
| `<lt>n` | n | `noice_all` | Recent messages, unfiltered (`views.recent`) |
| `<lt>e` | n | `noice_errors` | Recent messages, errors only (`views.recent`) |
| `<lt>c` | n | `capture` | Capture `:messages` to file + clipboard |
| `<lt>f` | n | `capture_file` | Capture `:messages` to file only |
| `<lt>y` | n | `capture_clipboard` | Capture `:messages` to clipboard only |
| `<lt>x` | n | `clear` | Close all debug view windows |

Two more `q`/`<Esc>` keymaps exist outside this table, both buffer-local and
not user-configurable: one inside the bare `:Debug` overview float
(`config.overview == "float"`, the default), and one built into the
`messages`/`noice_all`/`noice_errors` popup itself — `ui.kit.surface`'s own
`nice_quit` (ui.nvim installed) or `ui.kit.viewer`'s (the fallback dump, via
`lib.nvim.output.viewer`).

## User Commands

Single `:Debug {category} {action} [args]` dispatcher. Categories are gated
by `config.features.*`.

| command | desc |
| --- | --- |
| `:Debug` | Overview of enabled categories |
| `:Debug messages show\|capture\|clear` | Recent-messages popup, non-error entries (same as `<lt>m`) / capture `:messages` (file+clipboard) / close debug windows |
| `:Debug noice all\|errors` | Recent-messages popup, unfiltered / errors only (same as `<lt>n` / `<lt>e`; the category keeps its old name, Noice is not required) |
| `:Debug report buf\|tab\|win [id]` | Buffer / tab / window report to `:messages` |
| `:Debug autocmds runtime [event] [pat]` | Live `nvim_get_autocmds()` view |
| `:Debug autocmds sources [event=][sort=][impl=][summary=][freq=][root=][refresh=][qf=]` | Static source-code audit of `nvim_create_autocmd` call sites (Tree-sitter parser with text fallback; cached per root; `refresh=true` forces a rescan; `qf=true` sends `path:line` to the quickfix list) |
| `:Debug autocmds all [root=][refresh=][event=]` | Combined view: where each event is defined (sources) vs currently registered (runtime), plus a runtime-only diff |
| `:Debug inspect buffer [bufnr]` | Inspect buffer-scoped options and state. `[bufnr]` is a buffer number and completes against the existing buffers. |
| `:Debug inspect window [winid]` | Inspect window-scoped options and state |
| `:Debug inspect tab [tabnr]` | Inspect a tab page's windows and their buffers |
| `:Debug cursor state` | Print cursor / window / buffer state |
| `:Debug dump [varname]` | Recursively dump a global Lua var (or word under cursor) |
| `:Debug keylogger start [file]\|stop` | Log keys pressed in the current terminal buffer (optionally append to a file). `[file]` gets path completion — the file need not exist yet; the directory part completes on the way there. |
| `:Debug indent show` | Print indentation-related buffer options |
| `:Debug indent treesitter [true\|false]` | Prefer Tree-sitter indent, or turn cindent/smartindent on with false |
| `:Debug markdown inline` | Gather markdown inline-highlight debug info |
| `:Debug markdown log` | Open the most recent markdown debug log |
| `:Debug module reload` | Reload the Lua module of the current buffer |
| `:Debug proc start [threshold_ms]\|stop\|status\|log` | In-process tracer for `system()`/`jobstart` calls: log durations, plus a full Lua traceback for calls at or above the threshold (default 200ms) |
| `:Debug proc watch [seconds]` | (Windows) external process-tree watcher — every child process of this Neovim instance, however it was spawned |
| `:Debug performance startup [runs]` | Benchmark startup time and list the slowest sourced scripts |
| `:Debug neotree status\|exit\|restart\|backup-list\|backup-clean\|dryrun-toggle\|dryrun-report\|queue-status\|queue-clear` | Opt-in Neo-tree safety bridge (needs `features.neotree = true`) |
| `:Debug filetree watchers\|quarantine\|handles` | What the own tree of filetree.nvim holds on the disk: the `fs_event` handles with their askers and the event counters, the folders quarantined / changed / being read, and what is kept open and which folders that covers. Read from `require("filetree").fs_state()`; says so when filetree.nvim is not loaded or the own tree is not the active backend |
| `:Debug neotest adapters\|state\|file\|root\|framework\|discover` | neotest diagnostics: configured vs registered adapters, the current buffer's positions tree, which adapter's `is_test_file()` claims the file, the root each adapter's `root()` derives plus the marker files in it, the cwd's framework markers and `package.json` frameworks, discovered positions per adapter. Read-only; without neotest each degrades to one notification |
| `:Debug health` | Run `:checkhealth debugging` |

## Autocommands

None. `debugging.nvim` registers no autocommand of its own: the old
`DebugViewsAuto` group (`WinEnter`/`BufWinEnter` auto-refresh of a debug view,
`FileType messages/noice` close keymap) re-ran commands that no window of this
plugin uses any more and was removed together with its `views.autocmds` and
`views.timings` options. `:Debug autocmds` only *inspects* the autocommands of
other plugins.
