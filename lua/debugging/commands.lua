---@module 'debugging.commands'
--- The single unified :Debug command — dispatch + two-level completion.
---
--- `:Debug {category} {action} [args]`. Categories/actions are gated by the
--- active feature flags. Leaf logic lives in the submodules; this file only
--- routes to their exposed functions.
---
--- The actual `nvim_create_user_command` registration lives in
--- `debugging.bindings.usercmds`; this module only exposes `dispatch()` and
--- `complete()` for it to wire up.
---
---@see debugging.bindings.usercmds  Registration side of the dispatch/
--- registration split: builds the composer route tree from this module's
--- category/action registry and calls `dispatch()` from every route.

require("debugging.bindings.@types")

local notify = require("lib.nvim.notify").create("[debugging]")
local window = require("lib.nvim.window")
local config = require("debugging.config")

local M = {}

---Parse an optional handle argument (buffer/window id).
---
--- Returns `nil, true` when the argument was omitted (callers treat that as
--- "use the current/all handles"), and `nil, false` when it was present but
--- not a number — which used to fall through to the same `nil` and silently
--- ignore the typo (`:Debug report win abc` reported *all* windows).
---@internal
---@param raw string? Raw argument as typed by the user
---@return integer? id
---@return boolean ok
local function parse_id(raw)
  if raw == nil or raw == "" then
    return nil, true
  end
  local id = tonumber(raw)
  if not id or id ~= math.floor(id) then
    return nil, false
  end
  return id, true
end

-- Category -> { action -> fn }. Built lazily so leaf modules load on demand.
-- Each entry also carries an `actions` order list for completion.

---@internal
---@return table<string, Dbg.Bindings.RegistryEntry>
local function build_registry()
  return {
    messages = {
      feature = "views",
      actions = { "show", "capture", "clear" },
      run = {
        show = function()
          require("debugging.views").messages_show()
        end,
        capture = function()
          require("debugging.views").messages_capture()
        end,
        clear = function()
          require("debugging.views").windows_clear()
        end,
      },
    },
    noice = {
      feature = "views",
      actions = { "all", "errors" },
      run = {
        all = function()
          require("debugging.views").noice_all()
        end,
        errors = function()
          require("debugging.views").noice_errors()
        end,
      },
    },
    report = {
      feature = "reports",
      actions = { "buf", "tab", "win" },
      run = {
        buf = function()
          require("debugging.actions.reports").buf()
        end,
        tab = function()
          require("debugging.actions.reports").tab()
        end,
        win = function(args)
          local id, ok = parse_id(args[1])
          if not ok then
            notify.error(("invalid window id %q — expected a number"):format(args[1]))
            return
          end
          require("debugging.actions.reports").win(id)
        end,
      },
    },
    autocmds = {
      feature = "autocmds",
      actions = { "runtime", "sources", "all" },
      run = {
        runtime = function(args)
          require("debugging.autocmds.runtime").list(args[1], args[2])
        end,
        sources = function(args)
          require("debugging.autocmds.sources").run(table.concat(args, " "))
        end,
        all = function(args)
          require("debugging.autocmds.sources").all(table.concat(args, " "))
        end,
      },
    },
    inspect = {
      feature = "tools",
      actions = { "buffer", "window", "tab" },
      run = {
        buffer = function(args)
          local b, ok = parse_id(args[1])
          if not ok then
            notify.error(("invalid buffer id %q — expected a number"):format(args[1]))
            return
          end
          require("debugging.tools.buffer_inspector").inspect(b)
        end,
        window = function(args)
          local w, ok = parse_id(args[1])
          if not ok then
            notify.error(("invalid window id %q — expected a number"):format(args[1]))
            return
          end
          require("debugging.tools.buffer_inspector").window(w)
        end,
        tab = function(args)
          local t, ok = parse_id(args[1])
          if not ok then
            notify.error(("invalid tab number %q — expected a number"):format(args[1]))
            return
          end
          require("debugging.tools.buffer_inspector").tab(t)
        end,
      },
    },
    cursor = {
      feature = "tools",
      actions = { "state" },
      run = {
        state = function()
          require("debugging.tools.cursor.state").print()
        end,
      },
    },
    dump = {
      feature = "tools",
      actions = {}, -- free-form: :Debug dump [varname]
      run = {
        __default = function(args)
          require("debugging.tools.vardump").dump(args[1])
        end,
      },
    },
    keylogger = {
      feature = "terminals",
      actions = { "start", "stop" },
      run = {
        start = function(args)
          require("debugging.terminals.keylogger").start(args[1])
        end,
        stop = function()
          require("debugging.terminals.keylogger").stop()
        end,
      },
    },
    indent = {
      feature = "nvim_options",
      actions = { "show", "treesitter" },
      run = {
        show = function()
          require("debugging.nvim_options.indent_helpers").print_indent_options()
        end,
        treesitter = function(args)
          local raw = args[1]
          local enable
          if raw == nil or raw == "" or raw == "true" or raw == "1" then
            enable = true
          elseif raw == "false" or raw == "0" then
            enable = false
          else
            notify.error(("invalid argument %q — expected true or false"):format(raw))
            return
          end
          require("debugging.nvim_options.indent_helpers").prefer_treesitter_indent(enable)
        end,
      },
    },
    markdown = {
      feature = "markdown",
      actions = { "inline", "log" },
      run = {
        inline = function()
          local ok, res = require("debugging.markdown.inline_debug").gather()
          if not ok then
            notify.error("markdown inline: " .. tostring(res))
          end
        end,
        log = function()
          require("debugging.markdown.inline_debug").open_log()
        end,
      },
    },
    neotree = {
      feature = "neotree",
      actions = {
        "status",
        "exit",
        "restart",
        "backup-list",
        "backup-clean",
        "dryrun-toggle",
        "dryrun-report",
        "queue-status",
        "queue-clear",
      },
      run = {
        ["status"] = function()
          require("debugging.actions.neotree_safety").quarantine_status()
        end,
        ["exit"] = function()
          require("debugging.actions.neotree_safety").quarantine_exit()
        end,
        ["restart"] = function()
          require("debugging.actions.neotree_safety").restart_watchers()
        end,
        ["backup-list"] = function()
          require("debugging.actions.neotree_safety").backup_list()
        end,
        ["backup-clean"] = function()
          require("debugging.actions.neotree_safety").backup_clean()
        end,
        ["dryrun-toggle"] = function()
          require("debugging.actions.neotree_safety").dryrun_toggle()
        end,
        ["dryrun-report"] = function()
          require("debugging.actions.neotree_safety").dryrun_report()
        end,
        ["queue-status"] = function()
          require("debugging.actions.neotree_safety").queue_status()
        end,
        ["queue-clear"] = function()
          require("debugging.actions.neotree_safety").queue_clear()
        end,
      },
    },
    filetree = {
      feature = "filetree",
      actions = { "watchers", "quarantine", "handles" },
      run = {
        watchers = function()
          require("debugging.actions.filetree").watchers()
        end,
        quarantine = function()
          require("debugging.actions.filetree").quarantine()
        end,
        handles = function()
          require("debugging.actions.filetree").handles()
        end,
      },
    },
    neotest = {
      feature = "neotest",
      actions = { "adapters", "state", "file", "root", "framework", "discover" },
      run = {
        adapters = function()
          require("debugging.actions.neotest").adapters()
        end,
        state = function()
          require("debugging.actions.neotest").state()
        end,
        file = function()
          require("debugging.actions.neotest").file()
        end,
        root = function()
          require("debugging.actions.neotest").root()
        end,
        framework = function()
          require("debugging.actions.neotest").framework()
        end,
        discover = function()
          require("debugging.actions.neotest").discover()
        end,
      },
    },
    module = {
      feature = "module_reload",
      actions = { "reload" },
      run = {
        reload = function()
          require("debugging.actions.module_reload").reload_current()
        end,
      },
    },
    proc = {
      feature = "proc_trace",
      actions = { "start", "stop", "status", "log", "watch" },
      run = {
        start = function(args)
          require("debugging.tools.proc_trace").start(args)
        end,
        stop = function()
          require("debugging.tools.proc_trace").stop()
        end,
        status = function()
          require("debugging.tools.proc_trace").status()
        end,
        log = function()
          require("debugging.tools.proc_trace").open_log()
        end,
        watch = function(args)
          require("debugging.tools.proc_trace").watch(args)
        end,
      },
    },
    performance = {
      feature = "performance",
      actions = { "startup" },
      run = {
        startup = function(args)
          require("debugging.tools.startup").startup(args)
        end,
      },
    },
    health = {
      feature = "__always",
      actions = {},
      run = {
        __default = function()
          vim.cmd("checkhealth debugging")
        end,
      },
    },
  }
end

---@type table<string, any>|nil
local _registry = nil

---@return table
local function registry()
  if not _registry then
    _registry = build_registry()
  end
  return _registry
end

---Whether a category is enabled by the active feature flags.
---@param entry table
---@return boolean
local function enabled(entry)
  if entry.feature == "__always" then
    return true
  end
  return config.get().features[entry.feature] == true
end

---@return string[]  Enabled category names (stable order)
local function enabled_categories()
  local order = {
    "messages",
    "noice",
    "report",
    "autocmds",
    "inspect",
    "cursor",
    "dump",
    "keylogger",
    "indent",
    "markdown",
    "module",
    "proc",
    "performance",
    "neotree",
    "filetree",
    "neotest",
    "health",
  }
  local out = {}
  local reg = registry()
  for _, name in ipairs(order) do
    if reg[name] and enabled(reg[name]) then
      out[#out + 1] = name
    end
  end
  return out
end

-- Exposed for debugging.bindings.usercmds to build the composer route tree
-- (enabled-category snapshot, taken at setup() time) without duplicating
-- the registry/feature-gating logic.
M.registry = registry
M.enabled = enabled
M.enabled_categories = enabled_categories

-- Dispatch --------------------------------------------------------------------

---Render the overview lines in a centered, scrollable floating window.
--- Returns false if a float could not be opened (headless / no UI), so the
--- caller can fall back to a notification.
---@internal
---@param lines string[]
---@return boolean opened
local function overview_float(lines)
  local winid = window.make_scratch({
    lines = lines,
    filetype = "debugging-overview",
    title = " :" .. config.get().command .. " ",
    title_pos = "center",
    nice_quit = { force = true },
    wo = { cursorline = true },
  })
  return winid ~= nil
end

---@internal
---Show a compact overview when :Debug is called with no arguments.
---@return nil
local function overview()
  local lines = { "debugging.nvim — :Debug {category} {action}", "" }
  local reg = registry()
  for _, cat in ipairs(enabled_categories()) do
    local acts = reg[cat].actions
    local suffix = (#acts > 0) and ("  [" .. table.concat(acts, "|") .. "]") or ""
    lines[#lines + 1] = string.format("  %-10s%s", cat, suffix)
  end

  if config.get().overview == "float" and overview_float(lines) then
    return
  end
  notify.info(table.concat(lines, "\n"))
end

---@param fargs string[]
---@return nil
function M.dispatch(fargs)
  if #fargs == 0 then
    overview()
    return
  end

  local category = fargs[1]:lower()
  local entry = registry()[category]
  if not entry then
    notify.error(
      ("unknown category %q — try: %s"):format(category, table.concat(enabled_categories(), ", "))
    )
    return
  end
  if not enabled(entry) then
    notify.warn(("category %q is disabled (enable features.%s)"):format(category, entry.feature))
    return
  end

  local rest = vim.list_slice(fargs, 2)

  -- Free-form categories (dump, health) have a __default handler.
  if entry.run.__default then
    entry.run.__default(rest)
    return
  end

  local action = rest[1] and rest[1]:lower() or nil
  if not action then
    notify.error(
      ("usage: :%s %s {%s}"):format(
        config.get().command,
        category,
        table.concat(entry.actions, "|")
      )
    )
    return
  end

  local fn = entry.run[action]
  if not fn then
    notify.error(
      ("unknown action %q for %q — try: %s"):format(
        action,
        category,
        table.concat(entry.actions, "|")
      )
    )
    return
  end

  fn(vim.list_slice(rest, 2))
end

-- Completion ------------------------------------------------------------------

---@internal
---@param list string[]
---@param lead string
---@return string[]
local function filter(list, lead)
  if lead == "" then
    return list
  end
  local out = {}
  for i = 1, #list do
    if list[i]:sub(1, #lead) == lead then
      out[#out + 1] = list[i]
    end
  end
  return out
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline, _)
  local tokens = {}
  for t in cmdline:gmatch("%S+") do
    tokens[#tokens + 1] = t
  end
  local trailing = cmdline:sub(-1) == " "
  local committed = #tokens - (trailing and 0 or 1) - 1 -- minus command name

  if committed <= 0 then
    return filter(enabled_categories(), arglead)
  end

  local category = tokens[2] and tokens[2]:lower() or ""
  local entry = registry()[category]
  if not entry or not enabled(entry) then
    return {}
  end

  -- autocmds sources|all free-form args (event=/sort=/…)
  if category == "autocmds" and tokens[3] and committed >= 2 then
    local sub = tokens[3]:lower()
    if sub == "sources" or sub == "all" then
      return require("debugging.autocmds.sources").complete(arglead)
    end
  end

  if committed == 1 then
    return filter(entry.actions, arglead)
  end

  -- indent treesitter true/false
  if
    category == "indent"
    and tokens[3]
    and tokens[3]:lower() == "treesitter"
    and committed == 2
  then
    return filter({ "true", "false" }, arglead)
  end

  return {}
end

return M
