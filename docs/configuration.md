# Configuration

Full defaults:

```lua
require("debugging").setup({
  -- Per-category enable flags. `all = true` activates everything.
  features = {
    views        = true,   -- :Debug messages / noice / windows
    reports      = true,   -- :Debug report buf|tab|win
    autocmds     = true,   -- :Debug autocmds runtime|sources
    tools        = true,   -- :Debug inspect|cursor|dump
    terminals    = true,   -- :Debug keylogger
    nvim_options = true,   -- :Debug indent
    markdown     = true,   -- :Debug markdown
    module_reload = true,  -- :Debug module reload
    neotree      = false,  -- :Debug neotree … (config-specific, opt-in)
    neotest      = true,   -- :Debug neotest adapters|state|file|root|framework|discover
    proc_trace   = true,   -- :Debug proc start|stop|status|log|watch
    performance  = true,   -- :Debug performance startup
  },
  -- Terminals subsystem (:Debug keylogger).
  terminals = {
    keylogger = {
      logfile = nil,       -- append recorded keys here; nil = notify only.
                           -- `~`/env vars expand; `:Debug keylogger start {path}`
                           -- overrides this per-session.
    },
  },
  -- Neo-tree safety bridge targets (opt-in via features.neotree). Each is a
  -- module name to `require`, or an already-loaded table injected directly —
  -- so the bridge works without the private `config.neotree.*` layout.
  neotree = {
    quarantine = "config.neotree.watcher_quarantine",
    safety     = "config.neotree.safety",
  },
  -- neotest diagnostics (:Debug neotest …). Reads neotest's public state and
  -- the adapter tables from `neotest.setup()`; without neotest every action
  -- degrades to one notification.
  neotest = {
    output = "float",    -- "float": a scratch float per report; "notify": one notification
    markers = {          -- files worth reporting in a project root / the cwd
      "package.json", "vitest.config.ts", "vitest.config.js", "vitest.config.mjs",
      "vitest.workspace.ts", "jest.config.ts", "jest.config.js", "jest.config.mjs",
      "tsconfig.json", "go.mod", "Cargo.toml", "pyproject.toml", "pytest.ini",
      "setup.cfg", "TESTS/run.lua",
    },
    -- dependency names `:Debug neotest framework` looks for in package.json
    package_frameworks = { "vitest", "jest", "mocha", "ava", "playwright", "cypress" },
  },
  views = {
    keymaps  = { enable = true, prefix = "<lt>" },
    capture  = true,
    output_dir = nil,  -- default: stdpath("state")/debug_views
    recent   = {       -- the <lt>m / <lt>n / <lt>e popup, see "Recent-messages popup" below
      window_s = 10, min_entries = 5, order = "newest_last", collapsed_default = true,
      wrap_width = nil,
    },
  },
  command = "Debug",   -- name of the single unified command
  overview = "float",  -- how `:Debug` (no args) renders: "float" or "notify"
})

-- Shorthand: enable every category
require("debugging").setup({ all = true })
```

## Views keymaps

`views.keymaps = false` switches all of them off (the same as `{ enable = false }`); `true` keeps the defaults.

`views.keymaps` takes more than `enable` and `prefix`. Every key is declared
through `lib.nvim`'s keymap registry under an action name, and any of those
names can be given a different `lhs` — one string, a list of them, or `false`
to drop the key entirely. `prefix` still supplies the default for every action
left unnamed, so overriding one key no longer means moving all seven.

```lua
require("debugging").setup({
  views = {
    keymaps = {
      enable = true,
      prefix = "<leader>d",  -- supplies the default lhs for every action

      messages          = "<F12>",                -- one explicit lhs
      capture           = { "<leader>dc", "<F9>" },  -- or several
      capture_clipboard = false,                  -- or none at all
      -- noice_all, noice_errors, capture_file and clear keep the
      -- prefix-derived defaults: <leader>dn, <leader>de, <leader>df,
      -- <leader>dx
    },
  },
})
```

The action names are `messages`, `noice_all`, `noice_errors`, `capture`,
`capture_file`, `capture_clipboard` and `clear` — the same names listed in the
[bindings cheatsheet](BINDINGS.md#default-keymaps). Those seven are the only
action keys `views.keymaps` accepts besides `enable` and `prefix`; a misspelled
one (`mesages = "<F12>"`) is ignored with a warning that names the nearest
action, like any other unknown option (see [Validation](#validation)).

## Recent-messages popup

`views.recent` configures what `messages`/`noice_all`/`noice_errors` (the
`<m`/`<n`/`<e` keys) actually open: a popup backed by
[lib.nvim.messages](https://github.com/WKDSteve/lib.nvim), live and
paginated via `ui.kit.message_log` when [ui.nvim](https://github.com/WKDSteve/ui.nvim)
is installed, a static one-shot dump (`lib.nvim.output.viewer`) otherwise.

```lua
require("debugging").setup({
  views = {
    recent = {
      window_s = 10,            -- seconds of history shown on open; <C-j> / + adds that much older history (quiet stretches are skipped)
      min_entries = 5,          -- but never fewer than the newest N on open, however old (0 = strictly window_s)
      order = "newest_last",    -- or "newest_first"
      collapsed_default = true, -- every message folded to its header line; <CR> unfolds it
      wrap_width = nil,         -- text width of an unfolded message (default: min(100, columns - 12), at least 30)
    },
  },
})
```

What the popup can show is what `lib.nvim.messages` records: everything Neovim keeps in
`:messages` (`:echomsg`, `print()`, `:write`, errors incl. `E…` messages), the shell output of
`:!cmd`, and everything sent through `lib.nvim.notify`. Not recorded: a plain `:echo`
(Neovim does not keep it either) and a plain `vim.notify` while Noice owns it. Errors only
show under `<e` (and `<n`), never under `<m`.

That list assumes `lib.nvim.messages` has attached its `ext_messages` logger, which it does
only while a renderer runs (noice, or `setup({ renderer_override = true })`) and only after
the host config called `require("lib.nvim.messages").setup()`. debugging.nvim does not make
that call. Without it the popup holds only what went through `lib.nvim.notify` — no `:write`,
no Lua errors. See [installation.md](installation.md#what-feeds-the-recent-messages-popup);
`:checkhealth debugging` tells which case applies.

`messages` filters to non-error entries, `noice_all` is unfiltered, `noice_errors`
shows only errors — three views over the same live store, not three separate
logs.

### Keys inside the popup

Press `?` in the popup for this list as a cheatsheet (it opens over the popup,
`q` / `<Esc>` closes the sheet and returns to the log). The keys belong to
`ui.kit.message_log` ([ui.nvim's README](https://github.com/WKDSteve/ui.nvim/blob/main/lua/ui/kit/README.md#message-log-paginated-time-ordered-entry-list)).

| Key | Does |
| --- | --- |
| `<CR>`, `<Tab>`, `za` | expand / collapse the entry under the cursor (`▸` folded, `▾` open): the full message, wrapped to `wrap_width` |
| `zo` / `zc` | expand / collapse the entry under the cursor |
| `<C-l>`, `zR` | expand all entries |
| `<C-h>`, `<BS>`, `zM` | collapse all entries (first line only) |
| `<C-e>` | flip between all expanded / all collapsed |
| `<C-j>`, `+` | load older history (another `window_s` seconds; skips quiet stretches) |
| `<C-k>`, `-` | take the older page loaded last out again; `+` loads it back |
| `?`, `g?` | cheatsheet |
| `q`, `<Esc>` | close |

Folded, a message is one header line: wall-clock time and age, a tag (level
WARN/ERROR, the Vim error code such as `E492`, the message kind such as
`lua_error` or `shell_err`, the `lib.nvim.notify` source) and the title (its
first line, cut to fit). A message the header holds completely has nothing to
unfold.

The cursor stays on the entry you are reading when entries are expanded or
older ones are loaded; a cursor on the newest entry follows the live feed.

## Validation

Options are checked before they are merged. An unknown key — at the top
level or inside `features`, `terminals`, `neotree`, `neotest`, `views` — is ignored
with a warning that names the nearest known key (e.g. `views = { recen =
{...} }` → "did you mean 'views.recent'?"), and an option table given as
something other than a table falls back to that table's default. Both are
listed again under `:checkhealth debugging`.
