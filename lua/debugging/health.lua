---@module 'debugging.health'
--- :checkhealth debugging — environment, lib.nvim deps, and per-feature externals.

local M = {}

---Byte-identical fallback for `lib.nvim.health.check_require`, used only
---when lib.nvim itself (or this particular submodule) can't be loaded --
---the module-scope `require` this file used to have crashed `:checkhealth`
---outright in that case, before a single section could report anything,
---including the "lib.nvim is missing" message the rest of this file exists
---to show. This was this file's own helper before it got extracted into
---lib.nvim (see that module's header comment); every OTHER section below
---keeps working the same either way since only this fallback changes.
---@param mod string
---@param label string
---@param level "error"|"warn"|"info"
---@param advice? string[]
---@return nil
local function fallback_check_require(mod, label, level, advice)
  if pcall(require, mod) then
    vim.health.ok(label .. " (" .. mod .. ")")
  elseif level == "error" then
    vim.health.error(label .. " missing (" .. mod .. ")", advice)
  elseif level == "warn" then
    vim.health.warn(label .. " missing (" .. mod .. ")", advice)
  else
    vim.health.info(label .. " not found (" .. mod .. ")")
  end
end

---Report the `ext_messages` logger's attach state from `lib.nvim.messages.status()`, telling apart WHY it
---is (not) attached so the hint matches the cause: `renderer_override = false` (off by choice), noice loaded
---but not running, a renderer present without an attached logger (setup() not called), or no renderer at all.
---`vim.health.info()` takes only a message (no advice argument, unlike warn/error): every hint for an info
---entry is part of its text, or it would be dropped silently.
---@param status table `lib.nvim.messages.status()` (`attached`, `renderer`, `renderer_override`, `noice_loaded`, `count`)
---@return nil
local function report_attach_state(status)
  local stored = tonumber(status.count) or 0
  if status.attached then
    if status.renderer ~= nil then
      vim.health.ok(
        ("ext_messages logger attached (renderer: %s, %d entries stored)"):format(
          tostring(status.renderer),
          stored
        )
      )
    else
      vim.health.info(
        ("ext_messages logger attached, but no renderer keeps it (%d entries stored): "):format(
          stored
        )
          .. "it detaches on the next renderer check (noice stopped, or renderer_override changed)"
      )
    end
    return
  end

  local prefix = "ext_messages logger not attached (the popup holds only lib.nvim.notify entries, "
    .. "no :echo / :write / Lua error messages): "
  if status.renderer_override == false then
    vim.health.info(
      prefix
        .. "off by choice, setup({ renderer_override = false }); "
        .. "set renderer_override = true (or leave it nil with noice running) to record them"
    )
  elseif status.renderer ~= nil then
    vim.health.info(
      prefix
        .. ("a renderer is there (%s) but nothing attached the logger; "):format(
          tostring(status.renderer)
        )
        .. "call require('lib.nvim.messages').setup() in the host config"
    )
  elseif status.noice_loaded then
    vim.health.info(
      prefix
        .. "noice is loaded but not running (e.g. :Noice disable); "
        .. "the feed attaches again once noice runs, or with setup({ renderer_override = true })"
    )
  else
    vim.health.info(
      prefix
        .. "no renderer; call require('lib.nvim.messages').setup() in the host config "
        .. "with noice running, or setup({ renderer_override = true })"
    )
  end
end

---Report what the recent-messages popup (`<lt>m/n/e`) needs and how it will behave: whether
---`lib.nvim.messages` loads, whether `ui.kit.message_log` makes it live and paginated (else a static
---dump), and whether the `ext_messages` logger is attached right now (`lib.nvim.messages.status()`).
---@param check_require fun(mod: string, label: string, level: "error"|"warn"|"info", advice?: string[])
---@return nil
local function check_recent_popup(check_require)
  vim.health.start("debugging: recent popup")
  check_require("lib.nvim.messages", "recent popup: message store", "error", {
    'Install "WKDSteve/lib.nvim" (the popup reads its entries from lib.nvim.messages)',
  })

  local ok_kit, kit = pcall(require, "ui.kit")
  if ok_kit and type(kit) == "table" and type(kit.message_log) == "function" then
    vim.health.ok("ui.kit.message_log present: the popup is live and paginated")
  else
    vim.health.info("ui.kit.message_log not available: the popup shows a static dump (optional)")
  end

  local ok_messages, messages = pcall(require, "lib.nvim.messages")
  if not ok_messages or type(messages) ~= "table" then
    return
  end
  if type(messages.status) ~= "function" then
    vim.health.info(
      "lib.nvim.messages has no status() (older lib.nvim): attach state unknown; "
        .. "the ext_messages feed needs a running renderer (noice or renderer_override)"
    )
    return
  end

  local ok_status, status = pcall(messages.status)
  if not ok_status or type(status) ~= "table" then
    vim.health.warn("lib.nvim.messages.status() failed: " .. tostring(status))
    return
  end
  report_attach_state(status)
end

---Run every :checkhealth debugging section.
---@return nil
function M.check()
  local ok_lib_health, lib_health = pcall(require, "lib.nvim.health")
  local check_require = ok_lib_health and lib_health.check_require or fallback_check_require

  -- ── Core ────────────────────────────────────────────────────────────────
  vim.health.start("debugging: core")
  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.warn("Neovim 0.9+ recommended", { "Upgrade Neovim to 0.9+" })
  end
  if vim.g.loaded_debugging then
    vim.health.ok(
      "plugin loaded (vim.g.loaded_debugging = " .. tostring(vim.g.loaded_debugging) .. ")"
    )
  else
    vim.health.info("plugin guard not set (call require('debugging').setup())")
  end

  -- ── configuration ─────────────────────────────────────────────────────────
  vim.health.start("debugging: configuration")
  local config_issues = require("debugging.config").issues()
  if #config_issues == 0 then
    vim.health.ok("every setup() option was recognised")
  end
  for _, issue in ipairs(config_issues) do
    vim.health.warn(issue, { "Fix the key in require('debugging').setup({ ... })" })
  end

  -- ── lib.nvim dependency ───────────────────────────────────────────────────
  vim.health.start("debugging: lib.nvim")
  check_require(
    "lib.nvim.bindings.usercmd.composer",
    ":Debug command layer",
    "error",
    { 'Install "WKDSteve/lib.nvim"' }
  )
  check_require("lib.nvim.notify", "notify", "warn")
  check_require("lib.nvim.buf_win_tab.buffer_utils", "reports: buffer_utils", "warn")
  check_require("lib.nvim.buf_win_tab.windows_utils", "reports: windows_utils", "warn")
  check_require("lib.nvim.buf_win_tab.tabs_utils", "reports: tabs_utils", "warn")
  check_require("lib.nvim.buf_win_tab.capture", "views: capture", "info")
  check_require("lib.nvim.fs.write.to_file", "views: fs.write.to_file", "warn")
  check_require("lib.nvim.fs.path", "views: fs.path", "warn")
  check_require("lib.nvim.normalize", "views: normalize", "warn")
  check_require("lib.nvim.fs.collect_recursive", "autocmds sources: directory walk", "warn")
  check_require("lib.nvim.cache.memory", "autocmds sources: scan cache", "warn")
  check_require("lib.nvim.window", "views/overview: scratch + float windows", "warn")
  check_require("lib.lua.lazy", "lib.lua.lazy", "warn")

  -- ── Externals per feature ─────────────────────────────────────────────────
  vim.health.start("debugging: externals")

  local has_clipboard = false
  for _, bin in ipairs({ "pbcopy", "wl-copy", "xclip", "xsel", "clip.exe" }) do
    if vim.fn.executable(bin) == 1 then
      vim.health.ok("clipboard provider: " .. bin)
      has_clipboard = true
    end
  end
  if not has_clipboard then
    vim.health.warn("No clipboard provider (views capture → clipboard disabled)", {
      "Install pbcopy (macOS) / wl-copy (Wayland) / xclip (X11) / clip.exe (WSL)",
    })
  end

  -- Not `pcall(require, "nvim-treesitter")`: :checkhealth must not load a plugin as a side effect.
  -- The plugin itself never requires it either (diagnostics use core vim.treesitter); its only
  -- remaining role is the indentexpr the indent helpers hand over to.
  local ts_note = "(optional; only its indentexpr is used, diagnostics use core vim.treesitter)"
  if package.loaded["nvim-treesitter"] ~= nil then
    vim.health.ok("nvim-treesitter loaded " .. ts_note)
  elseif vim.api.nvim_get_runtime_file("lua/nvim-treesitter/init.lua", false)[1] then
    vim.health.ok("nvim-treesitter installed, not loaded yet " .. ts_note)
  else
    vim.health.info("nvim-treesitter not installed " .. ts_note)
  end

  -- Not `pcall(require, "noice")`: loading noice here (without its setup) would make the "recent popup"
  -- section below report "noice is loaded but not running" for a noice this very check just loaded.
  if package.loaded["noice"] ~= nil then
    vim.health.ok("noice loaded (views capture reads the Noice history first)")
  elseif vim.api.nvim_get_runtime_file("lua/noice/init.lua", false)[1] then
    vim.health.ok(
      "noice installed, not loaded yet (views capture reads the Noice history once it is)"
    )
  else
    vim.health.info("noice not installed: views capture falls back to :messages (optional)")
  end

  if pcall(require, "which-key") then
    vim.health.ok("which-key present (views keymap group label)")
  else
    vim.health.info("which-key not installed (optional)")
  end

  if pcall(require, "gitsuite") then
    vim.health.ok("gitsuite found: buffer report flags unresolved merge-conflict markers")
  else
    vim.health.info(
      "gitsuite not installed: buffer report skips the merge-conflict marker warning (optional)"
    )
  end

  -- ── Write permissions ─────────────────────────────────────────────────────
  -- the directory capture writes to (its default and `views.output_dir`), not a guess of the health check
  local state_dir = require("debugging.views.capture").base_dir
  if pcall(vim.fn.mkdir, state_dir, "p") then
    vim.health.ok("write permissions OK: " .. state_dir)
  else
    vim.health.error(
      "cannot write to: " .. state_dir,
      { "Check write permissions on stdpath('state')" }
    )
  end

  -- ── recent-messages popup ─────────────────────────────────────────────────
  -- Its own vim.health.start(): called only right before the next section starts, so it never swallows
  -- entries that belong to "externals" (it once sat mid-section and took which-key, gitsuite and the
  -- write-permission check with it).
  check_recent_popup(check_require)

  -- ── module_reload ─────────────────────────────────────────────────────────
  vim.health.start("debugging: module_reload")
  if vim.loader ~= nil then
    vim.health.ok("vim.loader available (Neovim 0.9+ cache reset supported)")
  else
    vim.health.info("vim.loader not available — only package.loaded cache will be cleared")
  end

  -- ── autocmds sources parser ───────────────────────────────────────────────
  vim.health.start("debugging: autocmds sources")
  if pcall(vim.treesitter.get_string_parser, "", "lua") then
    vim.health.ok("Lua Tree-sitter parser available (sources audit uses Tree-sitter)")
  else
    vim.health.info("no Lua Tree-sitter parser — sources audit falls back to the text parser")
  end

  -- ── performance (startup benchmark) ───────────────────────────────────────
  vim.health.start("debugging: performance")
  if vim.v.progpath and vim.v.progpath ~= "" then
    vim.health.ok("Neovim binary located for `:Debug performance startup`: " .. vim.v.progpath)
  else
    vim.health.warn("vim.v.progpath is empty — `:Debug performance startup` cannot spawn Neovim")
  end

  -- ── neotree bridge (opt-in, config-specific) ──────────────────────────────
  vim.health.start("debugging: neotree (opt-in)")
  local neotree = require("debugging.config").get().neotree or {}
  for _, key in ipairs({ "quarantine", "safety" }) do
    local target = neotree[key]
    if type(target) == "table" then
      vim.health.ok(("neotree.%s bridge injected directly (table)"):format(key))
    elseif type(target) == "string" then
      check_require(target, "neotree." .. key .. " bridge", "info")
    else
      vim.health.info(("neotree.%s not configured"):format(key))
    end
  end

  -- ── neotest diagnostics ───────────────────────────────────────────────────
  vim.health.start("debugging: neotest")
  if require("debugging.config").get().features.neotest then
    check_require("neotest", "neotest (for :Debug neotest …)", "info")
    local ok_cfg, ncfg = pcall(require, "neotest.config")
    if ok_cfg and type(ncfg) == "table" and type(ncfg.adapters) == "table" then
      vim.health.ok(("neotest.config.adapters: %d configured"):format(#ncfg.adapters))
    end
  else
    vim.health.info("features.neotest is off")
  end

  -- ── proc_trace (freeze diagnosis) ─────────────────────────────────────────
  vim.health.start("debugging: proc (freeze diagnosis)")
  check_require("lib.nvim.system.proc_trace", "lib.nvim.system.proc_trace", "warn")
  if vim.fn.has("win32") == 1 then
    local hits = vim.api.nvim_get_runtime_file("scripts/watch-nvim-procs.ps1", false)
    if hits[1] then
      vim.health.ok("bundled watcher script found: " .. hits[1])
    else
      vim.health.warn(
        "scripts/watch-nvim-procs.ps1 not found on the runtimepath",
        { "Reinstall debugging.nvim -- this script ships with the plugin" }
      )
    end
    if vim.fn.executable("pwsh") == 1 or vim.fn.executable("powershell") == 1 then
      vim.health.ok("PowerShell available (pwsh or powershell.exe) for `:Debug proc watch`")
    else
      vim.health.warn(
        "neither pwsh nor powershell.exe on PATH — `:Debug proc watch` will fail",
        { "Install PowerShell" }
      )
    end
  else
    vim.health.info(
      "`:Debug proc watch` is Windows-only (Win32 CIM process tree); "
        .. "`:Debug proc start/stop/status/log` work on every platform"
    )
  end

  -- ── composer route pre-flight ─────────────────────────────────────────────
  -- Guarded, unlike a plain `require(...)` here would be: the module-
  -- resolution check above already reports composer as missing (level
  -- "error") when it can't load, and that message is the point -- crashing
  -- straight into an uncaught Lua error one section later would blow away
  -- everything :checkhealth still had left to report (performance, neotree,
  -- proc) and replace the graceful warning with a raw traceback instead.
  local ok_composer, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  if ok_composer then
    composer.checkhealth("Debug")
  else
    vim.health.warn(
      "skipping :Debug route pre-flight -- composer unavailable (see lib.nvim section above)"
    )
  end
end

return M
