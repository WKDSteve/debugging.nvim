---@module 'debugging.config'
--- Runtime configuration store for debugging.nvim.
---
--- Merges user options over the immutable DEFAULTS and exposes the active config
--- via `get()`. No global state — the active table is module-local.

local DEFAULTS = require("debugging.config.DEFAULTS")

local M = {}

---Keys `setup()` accepts, recursively. `true` means "leaf -- any value of the
---right shape goes"; a nested table names that option group's own accepted
---keys, walked to whatever depth the group actually has, so a typo inside a
---nested table (e.g. `views.recent.window`) is caught exactly like a
---top-level one instead of vanishing into the merge unexamined.
---
---`neotree.quarantine`/`neotree.safety` and `neotest.markers`/
---`neotest.package_frameworks` stay `true` (leaves) on purpose: the former
---are polymorphic (module-name string or an already-loaded table, per
---DEFAULTS' comment), the latter are plain string arrays -- neither is a
---named option group, so recursing into them would misread numeric array
---indices as unknown option keys.
---@type table<string, true|table<string, any>>
local KNOWN = {
  features = {
    views = true,
    reports = true,
    autocmds = true,
    tools = true,
    terminals = true,
    nvim_options = true,
    markdown = true,
    neotree = true,
    filetree = true,
    neotest = true,
    module_reload = true,
    proc_trace = true,
    performance = true,
  },
  terminals = { keylogger = { logfile = true } },
  neotree = { quarantine = true, safety = true },
  filetree = { output = true },
  neotest = { output = true, markers = true, package_frameworks = true },
  views = {
    keymaps = { enable = true, prefix = true },
    capture = true,
    output_dir = true,
    recent = {
      window_s = true,
      min_entries = true,
      order = true,
      collapsed_default = true,
      wrap_width = true,
    },
  },
  command = true,
  overview = true,
  all = true, -- back-compat: bare `all = true` activates every feature category
}

-- `views.keymaps` also takes one entry per keymap action (`messages = "<F12>"`,
-- a list of keys, or `false`), see docs/configuration.md. The names come from
-- the list `debugging.bindings.keymaps` declares its actions from.
for _, action in ipairs(require("debugging.config.KEYMAP_ACTIONS")) do
  KNOWN.views.keymaps[action] = true
end

---@internal
---`key` with the nearest known one as a hint when there is a plausible one.
---@param key any
---@param known table<string, any>
---@param prefix string
---@return string
local function describe_unknown(key, known, prefix)
  local levenshtein = require("lib.lua.strings.distance").levenshtein
  local name = tostring(key)
  local best, best_distance = nil, nil
  for candidate in pairs(known) do
    local d = levenshtein(name, candidate)
    if d <= 3 and (best_distance == nil or d < best_distance) then
      best, best_distance = candidate, d
    end
  end
  if best then
    return string.format("unknown option '%s%s' (did you mean '%s%s'?)", prefix, name, prefix, best)
  end
  return string.format("unknown option '%s%s'", prefix, name)
end

---@internal
---Recursively drop what cannot be merged at this level, and say so, walking
---into nested option groups by their full dotted path. A misspelled key --
---at any depth -- would otherwise land in the active config as a dead field
---with the real default still in force, silently, since
---`tbl_deep_extend("force", ...)` accepts anything.
---@param user_tbl table  this level's user-supplied options
---@param known table<string, true|table>  this level's accepted keys (a KNOWN subtree)
---@param defaults table  this level's defaults, for nested "must be a table" checks
---@param prefix string  dotted path prefix for messages, e.g. "views." ("" at the root)
---@return table clean  the accepted subset, nested option tables copied
---@return string[] issues
local function sanitize_level(user_tbl, known, defaults, prefix)
  local clean, issues = {}, {}
  for key, value in pairs(user_tbl) do
    local known_entry = known[key]
    if known_entry == nil then
      issues[#issues + 1] = describe_unknown(key, known, prefix)
    elseif type(known_entry) == "table" then
      if type(value) ~= "table" then
        issues[#issues + 1] = string.format(
          "option '%s%s' must be a table, got %s -- using the default",
          prefix,
          key,
          type(value)
        )
      else
        local sub_defaults = type(defaults[key]) == "table" and defaults[key] or {}
        local nested, nested_issues =
          sanitize_level(value, known_entry, sub_defaults, prefix .. key .. ".")
        clean[key] = nested
        vim.list_extend(issues, nested_issues)
      end
    else
      clean[key] = value
    end
  end
  return clean, issues
end

---@internal
---Entry point for `sanitize_level()`: validates the whole user table against
---the root `KNOWN`/`DEFAULTS` trees and sorts the collected issues.
---@param user_opts table
---@return table clean
---@return string[] issues
local function sanitize(user_opts)
  local clean, issues = sanitize_level(user_opts, KNOWN, DEFAULTS, "")
  table.sort(issues)
  return clean, issues
end

---@internal
---`views.keymaps = false` is the conventional "none of these" spelling (REL-20);
---write it as the group table (`{ enable = false }`, `true` -> `{}`) the rest of
---the code reads, without touching the caller's table.
---@param user_opts table
---@return table
local function spell_out_switches(user_opts)
  local views = user_opts.views
  if type(views) ~= "table" then
    return user_opts
  end
  local out = vim.deepcopy(user_opts)
  if type(views.keymaps) == "boolean" then
    out.views.keymaps = require("lib.nvim.normalize").normalize_switch_group(views.keymaps)
  end
  return out
end

--- To the schema that `lib.lua.config` infers from `DEFAULTS`, the option groups `KNOWN` names are
--- open (`sanitize` walks them to whatever depth they have); an unknown top-level key is caught
--- there as well.
local ANY = "boolean|number|string|table|function"
---@type table<string, string|table>
local SCHEMA = {}
for key, known in pairs(KNOWN) do
  SCHEMA[key] = type(known) == "table" and { "table" } or ANY
end

-- Set by the normalize hook of the current `setup()`, read by its resolve hook.
local want_all = false

local cfg = require("lib.lua.config").new(DEFAULTS, {
  name = "debugging",
  schema = SCHEMA,
  -- polymorphic: a module name or an already-loaded module table, which must stay that very table
  opaque = { "neotree.quarantine", "neotree.safety" },
  normalize = function(opts, issues)
    -- Back-compat: a bare `all = true` activates every feature category (it is reported as an
    -- unknown key as well, which it always was, but it still counts).
    want_all = opts.all == true
    local spelled = spell_out_switches(opts)
    local clean, found = sanitize(spelled)
    for key in pairs(opts) do
      opts[key] = nil
    end
    for key, value in pairs(clean) do
      opts[key] = value
    end
    vim.list_extend(issues, found)
  end,
  resolve = function(current)
    if want_all then
      for k in pairs(current.features) do
        current.features[k] = true
      end
    end
  end,
  notify = function(message)
    require("lib.nvim.notify").create("[debugging]").warn(message)
  end,
})

---Merge user options over the defaults and store the result. Every call
---starts from `DEFAULTS`.
--- Back-compat: a bare `all = true` activates every feature category.
---
--- Unknown keys and mistyped option tables are reported once here and again
--- by `:checkhealth debugging` (see `issues()`); they never reach the merge.
---@param user_opts? Dbg.Config|table
---@return Dbg.Config
function M.setup(user_opts)
  want_all = false
  cfg.setup(type(user_opts) == "table" and user_opts or nil)
  return cfg.get()
end

---Return the active config, initializing it from DEFAULTS if setup() hasn't run yet.
---@return Dbg.Config
function M.get()
  return cfg.get()
end

---What the last `setup()` ignored: unknown keys and option tables of the
---wrong type, one human-readable line each. Empty when everything was
---accepted.
---@return string[]
function M.issues()
  return cfg.issues()
end

return M
