---@module 'debugging.config.DEFAULTS'
--- Immutable default configuration for debugging.nvim.
---
--- Single source of truth. `config/init.lua` deep-merges user options over a copy
--- of this table; it is never mutated at runtime.

---@type Dbg.Config
local DEFAULTS = {
  -- Per-category enable flags. `all = true` activates everything.
  features = {
    views = true, -- :Debug messages / noice / windows
    reports = true, -- :Debug report buf|tab|win
    autocmds = true, -- :Debug autocmds runtime|sources
    tools = true, -- :Debug inspect|cursor|dump
    terminals = true, -- :Debug keylogger
    nvim_options = true, -- :Debug indent
    markdown = true, -- :Debug markdown
    neotree = false, -- :Debug neotree … (config-specific, opt-in)
    neotest = true, -- :Debug neotest adapters|state|file|root|framework|discover
    module_reload = true, -- :Debug module reload
    proc_trace = true, -- :Debug proc start|stop|status|log|watch
    performance = true, -- :Debug performance startup
  },

  -- Terminals subsystem (:Debug keylogger).
  terminals = {
    keylogger = {
      -- Path to append recorded keys to. nil = notify only (no file).
      -- `~` and env vars are expanded. `:Debug keylogger start {path}`
      -- overrides this per-session.
      logfile = nil,
    },
  },

  -- Neo-tree safety bridge (opt-in via features.neotree). Each target is
  -- either a module name to `require`, or an already-loaded table injected
  -- directly — so the bridge works without the private `config.neotree.*`
  -- layout. Defaults keep the original hardcoded module names.
  neotree = {
    quarantine = "config.neotree.watcher_quarantine",
    safety = "config.neotree.safety",
  },

  -- neotest diagnostics (:Debug neotest …). Reads neotest's public state and
  -- the adapter tables from `neotest.setup()`; without neotest every action
  -- degrades to one notification.
  neotest = {
    -- "float" -- scratch float per report (default); "notify" -- one notification
    output = "float",
    -- Files whose presence in a project root / the cwd is worth reporting
    -- (`:Debug neotest root|framework`).
    markers = {
      "package.json",
      "vitest.config.ts",
      "vitest.config.js",
      "vitest.config.mjs",
      "vitest.workspace.ts",
      "jest.config.ts",
      "jest.config.js",
      "jest.config.mjs",
      "tsconfig.json",
      "go.mod",
      "Cargo.toml",
      "pyproject.toml",
      "pytest.ini",
      "setup.cfg",
      "TESTS/run.lua",
    },
    -- Dependency names `:Debug neotest framework` looks for in package.json.
    package_frameworks = { "vitest", "jest", "mocha", "ava", "playwright", "cypress" },
  },

  -- Views subsystem (keymaps, recent-messages popup, capture).
  views = {
    keymaps = { enable = true, prefix = "<lt>" },
    capture = true,
    output_dir = nil, -- defaults to stdpath("state")/debug_views inside capture
    -- The <m>/<n>/<e> recent-messages popup (lib.nvim.messages + ui.kit.message_log
    -- when ui.nvim is installed, a static lib.nvim.output.viewer dump otherwise).
    recent = {
      window_s = 10, -- seconds of history shown on open; <C-j> / + adds that much older history
      min_entries = 5, -- ...but never fewer than this many entries on open, however old (0 = strictly window_s)
      order = "newest_last", -- or "newest_first"
      collapsed_default = true, -- one header line per message; <CR> unfolds the full, wrapped text
      wrap_width = nil, -- text width of an unfolded message (default: min(100, columns - 12))
    },
  },

  command = "Debug", -- name of the single unified user command

  -- How `:Debug` with no arguments renders the category overview:
  --   "float"  -- scrollable floating window (default), q/<Esc> to close
  --   "notify" -- single lib.nvim notification (previous behaviour)
  overview = "float",
}

return DEFAULTS
