# Tools

The individual `:Debug` categories beyond the dispatcher, the views and the
autocmd audit: state reports and inspectors, the terminal keylogger, indent
and markdown diagnostics, module reloading, the startup benchmark, and the
opt-in Neo-tree bridge.

## Reports — a printed snapshot

`:Debug report buf|tab|win [id]` prints a snapshot of a buffer, a window, or
the current tab's window/buffer layout straight to `:messages`. It is the
fastest way to see scoped options and state when all you want is to paste them
somewhere or glance and move on — no window opens.

- **Module:** `actions/reports.lua` (built on `lib.nvim.buf_win_tab.*`)
- **Config:** `opts.features.reports`
- **Usercmds:** `:Debug report buf|tab|win [id]` — `win` completes against the
  open window ids

## Inspect, cursor, dump — scoped browsing

The everyday "what does Neovim think is going on here" trio: buffer, window
and tab page inspection of options and state; a cursor/window/buffer state
printer; and a recursive dumper for any global Lua value, or the word under the
cursor when no name is given.

Where `report` prints once, `inspect` opens a proper scoped view — reach for it
when you are comparing values across buffers or windows rather than capturing
one.

- **Module:** `tools/buffer_inspector/init.lua` (`M.inspect`, `M.window`,
  `M.tab`), `tools/cursor/state.lua` (`M.print`), `tools/vardump/init.lua`
  (`M.dump`)
- **Config:** `opts.features.tools`
- **Usercmds:** `:Debug inspect buffer|window|tab [id]`, `:Debug cursor state`,
  `:Debug dump [varname]` — `inspect buffer` and `inspect window` complete
  their id

## Terminal keylogger

Logs the keys pressed inside the current terminal buffer. With no logfile
configured it only notifies as they are pressed; give it a path — in `setup()`
or as an argument — and it appends to disk instead, for a record that outlives
the session. `~` and environment variables are expanded, and the command
argument overrides the configured default for that run only.

- **Module:** `terminals/keylogger.lua` (`M.start`, `M.stop`,
  `resolve_logfile`)
- **Config:** `opts.features.terminals`,
  `opts.terminals.keylogger.logfile` (default `nil` = notify only)
- **Usercmds:** `:Debug keylogger start [file]`, `:Debug keylogger stop` —
  `[file]` gets path completion

## Indent diagnostics

Prints the current buffer's indentation-related options, and can force
Tree-sitter-driven indent on or restore `cindent`/`smartindent`.

- **Module:** `nvim_options/indent_helpers.lua`
- **Config:** `opts.features.nvim_options`
- **Usercmds:** `:Debug indent show`, `:Debug indent treesitter [true|false]`

## Markdown inline-highlight debug

Gathers debug information for markdown inline highlighting — the extmark and
syntax state behind rendered inline styling — and opens the most recent debug
log. The Tree-sitter section of the log (language, parser installed, whether
Tree-sitter highlights the buffer and with which language) comes from Neovim's
core `vim.treesitter` API, so it works without nvim-treesitter. It is
read-only: gathering never creates a parser for the buffer or attaches one to
it, so it reports the buffer as it was.

- **Module:** `markdown/inline_debug.lua`
- **Config:** `opts.features.markdown`
- **Usercmds:** `:Debug markdown inline`, `:Debug markdown log`

## Module reload

Reloads the Lua module backing the current buffer: evict it from
`package.loaded`, then `require` it fresh. This is the fast inner loop for
iterating on a plugin's own source without restarting Neovim — with the limit
that it clears only that one module, so anything that already holds a local
reference to the old table keeps running against stale code.

- **Module:** `actions/module_reload.lua`
- **Config:** `opts.features.module_reload`
- **Usercmds:** `:Debug module reload`

## Startup benchmark

Spawns a headless Neovim under `--startuptime`, parses the resulting log, and
reports the total startup time — optionally averaged over N runs — plus the
slowest sourced scripts. Each measurement runs in its own subprocess and quits
immediately, so it has no effect on the current session. Averaging is the
version worth running: run-to-run jitter on a real machine makes a single
sample a weak answer to "did that config change help".

- **Module:** `tools/startup.lua` (`M.parse`, `M.startup`)
- **Config:** `opts.features.performance` (default `true`)
- **Usercmds:** `:Debug performance startup [runs]`

## Neo-tree safety bridge (opt-in)

A bridge to a user-specific Neo-tree watcher-quarantine and safety layer:
quarantine status/exit/restart, backup list/clean, dry-run toggle/report, and
queue status/clear.

Both targets are injectable — each is either a module name to `require` or an
already-loaded table — so the bridge does not depend on one particular private
`config.neotree.*` layout. Resolution is `pcall`-guarded, so with the feature
on but the target config absent, every action degrades to a clear warning
notification instead of an error. That is deliberate, and it means "the command
ran without an error" is not the same as "the command did something". Disabled
by default, because the config it talks to lives outside this plugin.

- **Module:** `actions/neotree_safety.lua` (`need`)
- **Config:** `opts.features.neotree` (default `false`),
  `opts.neotree.quarantine`, `opts.neotree.safety`
- **Usercmds:** `:Debug neotree status|exit|restart|backup-list|backup-clean|dryrun-toggle|dryrun-report|queue-status|queue-clear`
  — see [BINDINGS.md](../BINDINGS.md#user-commands)

## The file layer of filetree.nvim's own tree

"Is it this Neovim that keeps the folder busy?" and "why does the tree not
show the change?" both come down to what the own tree of
[filetree.nvim](https://github.com/WKDSteve/filetree.nvim) (`adapter =
"native"`) holds on the disk. Three reports print it: `watchers` lists the
open `fs_event` handles with the number of askers per folder, how the tree
watches (one handle per root, or one per folder read) and the event counters
since Neovim started; `quarantine` lists the folders held back after an event
storm, the ones with a change that is not reported yet, and the ones being
read; `handles` lists everything kept open below the roots, the handles
released for a running file operation, and says which folders a handle covers.

Everything is read from one function, `require("filetree").fs_state()`, and
nothing is started or changed. filetree.nvim is not loaded for it: a session
that has not loaded it holds nothing, and the report says so in one
notification. So does a filetree.nvim from before `fs_state()`, and one whose
`fs_state()` fails. Every report says when the own tree is not the active
backend (what is listed then was left by a tree opened before the backend
changed). Reports open in a scratch float (`q` closes) or, with
`filetree.output = "notify"`, in one notification.

- **Module:** `actions/filetree.lua`
- **Config:** `opts.features.filetree` (default `true`), `opts.filetree.output`
- **Usercmds:** `:Debug filetree watchers|quarantine|handles`
  — see [BINDINGS.md](../BINDINGS.md#user-commands)

## neotest diagnostics

"Why is neotest not finding my tests?" has a fixed order of suspects, and
the six `:Debug neotest` actions walk it: `adapters` shows the adapters
handed to `neotest.setup()` next to the ids neotest has actually registered
(an adapter registers only once it claims a root for an opened file, so an
empty second list with a full first one is a hint, not a bug); `state` is
what neotest knows about the current buffer, including whether any adapter
holds a positions tree for it; `file` asks every configured adapter's own
`is_test_file(path)` about the current file — the adapter's answer, not a
pattern match on its id; `root` asks each adapter's `root(dir)` for the
project it derives and lists the marker files in that root; `framework`
reads the cwd (`vim.fs.dir`, not `glob`, so a path with `[` in it still
lists) for the same markers and names the test frameworks `package.json`
mentions; `discover` counts positions per registered adapter by type.

Everything is read-only and every neotest access is `pcall`-guarded: without
neotest each action is one notification, and a neotest that renamed a field
degrades to "?" in the report rather than an error. The reports open in a
scratch float (`q` closes) or, with `neotest.output = "notify"`, in one
notification; each action also returns its lines.

- **Module:** `actions/neotest.lua`
- **Config:** `opts.features.neotest` (default `true`), `opts.neotest.output`,
  `opts.neotest.markers`, `opts.neotest.package_frameworks`
- **Usercmds:** `:Debug neotest adapters|state|file|root|framework|discover`
