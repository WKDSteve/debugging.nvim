-- TESTS/health_spec.lua
-- `health.lua` is intentionally NOT given full coverage (see TESTS/README.md
-- "Deliberately left untested") -- it is a declarative :checkhealth reporter
-- whose failure mode is a wrong hint in :checkhealth output, and exercising
-- every branch would mock every external it probes without asserting
-- anything about this plugin's own logic.
--
-- Scenarios 1 and 2 pin two real crashes found in a 2026-09-18 re-audit; scenarios 3 to 12 pin the
-- "recent popup" section (its requirements, the logger attach state and its cause, and which
-- entries the section holds); 13 to 15 the externals noice line; 16 to 18 the nvim-treesitter line.
-- Every popup run also checks that no info() entry carries an advice argument (Neovim's info()
-- drops it).

---Run `body` with `vim.health.{start,ok,warn,error,info}` captured into a
---list instead of printed, and `require` swapped for `stub_require` for the
---duration -- both restored afterward even if `body` throws.
---@param stub_require fun(orig_require: function, mod: string, ...): any
---@param body fun(seen: {level: string, msg: string, advice: any}[], orig_require: function): nil
local function with_health_capture(stub_require, body)
  local seen = {}
  local fields = { "start", "ok", "warn", "error", "info" }
  local orig_health = {}
  for _, f in ipairs(fields) do
    orig_health[f] = vim.health[f]
    vim.health[f] = function(msg, advice)
      seen[#seen + 1] = { level = f, msg = tostring(msg), advice = advice }
    end
  end

  local orig_require = _G.require
  _G.require = function(mod, ...)
    return stub_require(orig_require, mod, ...)
  end

  local ok, err = pcall(body, seen, orig_require)

  _G.require = orig_require
  for _, f in ipairs(fields) do
    vim.health[f] = orig_health[f]
  end
  if not ok then
    error(err, 0)
  end
end

return function(H)
  -- Scenario 1: `M.check()`'s last section called
  -- `require("lib.nvim.bindings.usercmd.composer").checkhealth("Debug")`
  -- unguarded -- even though the module-resolution section a few lines above
  -- it already probes that exact same module via `check_require(..., "error",
  -- ...)` and would have already reported it missing. If composer really is
  -- unavailable, that bare `require` throws an uncaught Lua error instead of
  -- degrading to the warning already issued, which also means every section
  -- after it (neotree, proc) never runs and :checkhealth shows a raw
  -- traceback instead of a graceful report.
  --
  -- Composer is faked missing by swapping the global `require` for the
  -- duration of the call: both `check_require`'s internal `pcall(require,
  -- mod)` and the composer pre-flight's own `require(...)` resolve `require`
  -- live at call time (neither captures it as an upvalue at module load), so
  -- this reaches both without needing package.loaded gymnastics.
  with_health_capture(function(orig_require, mod, ...)
    if mod == "lib.nvim.bindings.usercmd.composer" then
      error("module '" .. mod .. "' not found (health_spec stub)", 0)
    end
    return orig_require(mod, ...)
  end, function(seen, orig_require)
    local health = orig_require("debugging.health")

    local ok_check, err_check = pcall(health.check)
    H.ok(
      ok_check,
      "check(): composer missing must degrade to the warning already issued, not crash -- got: "
        .. tostring(err_check)
    )

    local found_error, found_warn = false, false
    for _, entry in ipairs(seen) do
      if entry.level == "error" and entry.msg:match("composer") then
        found_error = true
      end
      if entry.level == "warn" and entry.msg:match("composer") then
        found_warn = true
      end
    end
    H.ok(found_error, "check(): module-resolution section still reports composer missing")
    H.ok(found_warn, "check(): composer pre-flight degrades to a warn instead of an uncaught error")
  end)

  -- Scenario 2: `health.lua` used to `require("lib.nvim.health")` at MODULE
  -- LOAD TIME (`local check_require = require("lib.nvim.health").check_require`,
  -- outside `M.check()`), so an older/partial lib.nvim missing just this one
  -- submodule crashed `require("debugging.health")` itself -- before a single
  -- section of the report, including the one meant to explain that lib.nvim
  -- is the problem, ever ran. Fixed by moving the require inside `M.check()`
  -- and falling back to a local copy of the same helper on failure, so every
  -- OTHER section (externals, write permissions, neotree, proc, composer)
  -- keeps reporting normally even when lib.nvim.health specifically can't be
  -- loaded.
  --
  -- `package.loaded["debugging.health"]` is cleared first so this scenario
  -- doesn't just observe scenario 1's already-cached module table --
  -- `require("lib.nvim.health")` now happens inside `M.check()`, not at
  -- module load, so this also verifies the fresh-require actually re-runs.
  with_health_capture(function(orig_require, mod, ...)
    if mod == "lib.nvim.health" then
      error("module '" .. mod .. "' not found (health_spec stub)", 0)
    end
    return orig_require(mod, ...)
  end, function(seen, orig_require)
    package.loaded["debugging.health"] = nil
    local health = orig_require("debugging.health")

    local ok_check, err_check = pcall(health.check)
    H.ok(
      ok_check,
      "check(): lib.nvim.health missing must degrade to a fallback reporter, not crash on require -- got: "
        .. tostring(err_check)
    )

    local found_composer_report = false
    for _, entry in ipairs(seen) do
      if entry.msg:match("composer") then
        found_composer_report = true
      end
    end
    H.ok(
      found_composer_report,
      "check(): the lib.nvim.bindings.usercmd.composer probe still ran via the fallback check_require"
    )
  end)

  -- Scenario 3..6: the "debugging: recent popup" section. It reports the popup's requirements:
  -- the message store, `ui.kit.message_log` (live vs static) and the logger's attach state from
  -- `lib.nvim.messages.status()`. Both modules are stubbed through `require`; only this
  -- section's own branching is asserted (not the other sections).
  ---@param seen {level: string, msg: string, advice: any}[]
  ---@param level string
  ---@param pattern string
  ---@return {level: string, msg: string, advice: any}|nil
  local function find(seen, level, pattern)
    for _, entry in ipairs(seen) do
      if entry.level == level and entry.msg:find(pattern, 1, true) then
        return entry
      end
    end
    return nil
  end

  ---@param kit table|nil `nil` = ui.kit cannot be required
  ---@param messages table|nil `nil` = lib.nvim.messages cannot be required
  ---@param body fun(seen: {level: string, msg: string, advice: any}[])
  local function with_popup_stubs(kit, messages, body)
    with_health_capture(function(orig_require, mod, ...)
      if mod == "ui.kit" or mod == "lib.nvim.messages" then
        local stub = mod == "ui.kit" and kit or messages
        if stub == nil then
          error("module '" .. mod .. "' not found (health_spec stub)", 0)
        end
        return stub
      end
      return orig_require(mod, ...)
    end, function(seen, orig_require)
      package.loaded["debugging.health"] = nil
      local health = orig_require("debugging.health")
      local ok_check, err_check = pcall(health.check)
      H.ok(ok_check, "check(): must not crash -- got: " .. tostring(err_check))
      -- Neovim's `vim.health.info(msg)` takes ONE argument: an advice list passed to it is dropped
      -- without a trace in real :checkhealth output, while this capture stub would keep it. So no info
      -- entry may carry advice; its hint belongs in the message text.
      for _, entry in ipairs(seen) do
        if entry.level == "info" and entry.advice ~= nil then
          H.ok(false, "info() called with an advice argument (dropped by Neovim): " .. entry.msg)
        end
      end
      body(seen)
    end)
  end

  ---The section (`vim.health.start()` title) an entry was reported under.
  ---@param seen {level: string, msg: string, advice: any}[]
  ---@param target {level: string, msg: string, advice: any}|nil
  ---@return string|nil
  local function section_of(seen, target)
    local current = nil ---@type string|nil
    for _, entry in ipairs(seen) do
      if entry.level == "start" then
        current = entry.msg
      elseif entry == target then
        return current
      end
    end
    return nil
  end

  ---@param seen {level: string, msg: string, advice: any}[]
  ---@param pattern string
  ---@return {level: string, msg: string, advice: any}|nil
  local function find_any(seen, pattern)
    for _, entry in ipairs(seen) do
      if entry.level ~= "start" and entry.msg:find(pattern, 1, true) then
        return entry
      end
    end
    return nil
  end

  local attached_noice = {
    status = function()
      return { attached = true, renderer = "noice", count = 7 }
    end,
  }

  -- 3: live popup, logger attached.
  with_popup_stubs({ message_log = function() end }, attached_noice, function(seen)
    H.ok(
      find(seen, "ok", "popup is live and paginated"),
      "recent popup: ui.kit.message_log -> live ok"
    )
    H.ok(
      find(seen, "ok", "logger attached (renderer: noice, 7 entries stored)"),
      "recent popup: attached logger -> ok with renderer and count"
    )
    H.ok(
      not find(seen, "info", "not attached"),
      "recent popup: an attached logger must not also report 'not attached'"
    )
  end)

  -- 4: static popup, logger not attached and no renderer at all: info whose TEXT carries the hint
  -- (setup + renderer) -- info() has no advice argument -- never an error.
  with_popup_stubs(nil, {
    status = function()
      return { attached = false, renderer = nil, count = 0, noice_loaded = false }
    end,
  }, function(seen)
    H.ok(find(seen, "info", "static dump"), "recent popup: no ui.kit -> info about the static dump")
    local detached = find(seen, "info", "logger not attached")
    H.ok(detached, "recent popup: detached logger -> info")
    H.ok(
      detached
        and detached.msg:find("no renderer;", 1, true)
        and detached.msg:find("require('lib.nvim.messages').setup()", 1, true)
        and detached.msg:find("renderer_override = true", 1, true),
      "recent popup: detached logger without a renderer names setup() and the renderer in its text"
    )
    H.ok(
      not find(seen, "error", "logger"),
      "recent popup: a detached logger is never reported as an error"
    )
    H.ok(
      not find(seen, "ok", "popup is live and paginated"),
      "recent popup: without ui.kit the popup is not reported live"
    )
  end)

  -- 5: an older lib.nvim without status(): text-only hint, no crash.
  with_popup_stubs({ message_log = function() end }, {}, function(seen)
    H.ok(
      find(seen, "info", "has no status()"),
      "recent popup: lib.nvim.messages without status() -> info (attach state unknown)"
    )
  end)

  -- 6: lib.nvim.messages missing entirely: error for the store, no further status probing.
  with_popup_stubs({ message_log = function() end }, nil, function(seen)
    H.ok(
      find(seen, "error", "recent popup: message store missing"),
      "recent popup: lib.nvim.messages missing -> error"
    )
    H.ok(
      not find(seen, "ok", "logger attached"),
      "recent popup: no attach report without lib.nvim.messages"
    )
    -- The early return: without it the require error STRING flows on, has no `status` and is
    -- misreported as "an older lib.nvim without status()".
    H.ok(
      not find_any(seen, "has no status()") and not find_any(seen, "status() failed"),
      "recent popup: lib.nvim.messages missing -> no further status probing"
    )
  end)

  -- 7: status() throwing degrades to a warning, not a crashed :checkhealth.
  with_popup_stubs(nil, {
    status = function()
      error("boom", 0)
    end,
  }, function(seen)
    H.ok(
      find(seen, "warn", "status() failed"),
      "recent popup: a throwing status() -> warn instead of an uncaught error"
    )
  end)

  -- the write check names the directory capture writes to (a changed `capture.base_dir` moves it)
  do
    local capture = require("debugging.views.capture")
    local real = capture.base_dir
    capture.base_dir = vim.fn.tempname() .. "/dumps"
    with_popup_stubs({ message_log = function() end }, attached_noice, function(seen)
      H.ok(find_any(seen, "dumps"), "health: the write check names capture's directory")
    end)
    capture.base_dir = real
  end

  -- 8: section membership. "debugging: recent popup" holds only the popup's own entries; which-key,
  -- gitsuite, noice and the debug_views write check stay under "debugging: externals" (the popup
  -- section once started mid-externals and swallowed them).
  with_popup_stubs({ message_log = function() end }, attached_noice, function(seen)
    local popup_section = "debugging: recent popup"
    for _, pattern in ipairs({
      "recent popup: message store",
      "popup is live and paginated",
      "logger attached (renderer: noice",
    }) do
      local entry = find_any(seen, pattern)
      H.ok(entry, "sections: popup entry reported: " .. pattern)
      H.eq(
        section_of(seen, entry),
        popup_section,
        "sections: '" .. pattern .. "' in the popup section"
      )
    end
    -- "views capture": the externals noice line ("noice" alone also matches the popup's attach line).
    for _, pattern in ipairs({
      "which-key",
      "gitsuite",
      "debug_views",
      "views capture",
      "nvim-treesitter",
    }) do
      local entry = find_any(seen, pattern)
      H.ok(entry, "sections: externals entry reported: " .. pattern)
      H.eq(
        section_of(seen, entry),
        "debugging: externals",
        "sections: '" .. pattern .. "' stays in the externals section"
      )
    end
    for _, entry in ipairs(seen) do
      if entry.level ~= "start" and section_of(seen, entry) == popup_section then
        H.ok(
          entry.msg:find("popup", 1, true) or entry.msg:find("ext_messages", 1, true),
          "sections: only popup entries in the popup section, got: " .. entry.msg
        )
      end
    end
  end)

  -- 9..12: the attach state's cause picks the hint (status() fields renderer, renderer_override,
  -- noice_loaded), so the text never says "call setup()" when setup() already decided otherwise.
  -- 9: attached, but no renderer keeps it (it detaches on the next check): no "renderer: nil".
  with_popup_stubs(nil, {
    status = function()
      return { attached = true, renderer = nil, count = 3, noice_loaded = false }
    end,
  }, function(seen)
    H.ok(
      find(seen, "info", "no renderer keeps it (3 entries stored)"),
      "attach: attached without a renderer -> info that it detaches"
    )
    H.ok(not find_any(seen, "renderer: nil"), "attach: never prints 'renderer: nil'")
  end)

  -- 10: renderer_override = false: off by choice, setup() already ran.
  with_popup_stubs(nil, {
    status = function()
      return { attached = false, renderer = nil, renderer_override = false, noice_loaded = true }
    end,
  }, function(seen)
    local entry = find(seen, "info", "logger not attached")
    H.ok(
      entry and entry.msg:find("off by choice", 1, true),
      "attach: renderer_override = false -> 'off by choice'"
    )
    H.ok(
      entry and not entry.msg:find("setup() in the host config", 1, true),
      "attach: renderer_override = false -> no 'call setup()' hint"
    )
  end)

  -- 11: a renderer is available but nothing attached: setup() was not called.
  with_popup_stubs(nil, {
    status = function()
      return { attached = false, renderer = "noice", noice_loaded = true }
    end,
  }, function(seen)
    local entry = find(seen, "info", "logger not attached")
    H.ok(
      entry
        and entry.msg:find("a renderer is there (noice)", 1, true)
        and entry.msg:find("setup() in the host config", 1, true),
      "attach: renderer present, not attached -> 'call setup()'"
    )
  end)

  -- 12: noice loaded but not running (`:Noice disable`).
  with_popup_stubs(nil, {
    status = function()
      return { attached = false, renderer = nil, noice_loaded = true }
    end,
  }, function(seen)
    local entry = find(seen, "info", "logger not attached")
    H.ok(
      entry and entry.msg:find("noice is loaded but not running", 1, true),
      "attach: noice loaded, not running -> says so"
    )
  end)

  -- 13..15: the externals noice line (views capture reads the Noice history first). Probed WITHOUT
  -- `require("noice")`: loading noice from :checkhealth would make the popup section report a noice
  -- "loaded but not running" that this very check loaded.
  ---@param loaded any `package.loaded["noice"]` for the run
  ---@param on_rtp boolean whether `lua/noice/init.lua` is found on the runtimepath
  ---@param body fun(seen: {level: string, msg: string, advice: any}[], required: boolean)
  local function with_noice(loaded, on_rtp, body)
    local orig_loaded, orig_preload = package.loaded["noice"], package.preload["noice"]
    local orig_rtf = vim.api.nvim_get_runtime_file
    local required = false
    package.loaded["noice"] = loaded
    package.preload["noice"] = function()
      required = true
      return {}
    end
    vim.api.nvim_get_runtime_file = function(name, all)
      if name == "lua/noice/init.lua" then
        return on_rtp and { "/fake/lua/noice/init.lua" } or {}
      end
      return orig_rtf(name, all)
    end
    local ok, err = pcall(with_popup_stubs, nil, attached_noice, function(seen)
      body(seen, required)
    end)
    vim.api.nvim_get_runtime_file = orig_rtf
    package.loaded["noice"] = orig_loaded
    package.preload["noice"] = orig_preload
    if not ok then
      error(err, 0)
    end
  end

  -- 13: noice already loaded.
  with_noice({}, false, function(seen)
    H.ok(find(seen, "ok", "noice loaded (views capture"), "noice: loaded -> ok")
  end)

  -- 14: noice installed but not loaded: reported, and the check does not load it.
  with_noice(nil, true, function(seen, required)
    H.ok(find(seen, "ok", "noice installed, not loaded yet"), "noice: on the rtp -> ok, not loaded")
    H.ok(not required, "noice: the health check must not require() noice")
  end)

  -- 15: noice not installed: optional info about the :messages fallback.
  with_noice(nil, false, function(seen)
    H.ok(
      find(seen, "info", "noice not installed: views capture falls back to :messages"),
      "noice: missing -> info about the :messages fallback"
    )
  end)

  -- 16..18: the externals nvim-treesitter line. Probed WITHOUT `require("nvim-treesitter")`:
  -- :checkhealth must not load it; the message names its one remaining use (indentexpr).
  ---@param loaded any `package.loaded["nvim-treesitter"]` for the run
  ---@param on_rtp boolean whether `lua/nvim-treesitter/init.lua` is found on the runtimepath
  ---@param body fun(seen: {level: string, msg: string, advice: any}[], required: boolean)
  local function with_ts(loaded, on_rtp, body)
    local mod = "nvim-treesitter"
    local orig_loaded, orig_preload = package.loaded[mod], package.preload[mod]
    local orig_rtf = vim.api.nvim_get_runtime_file
    local required = false
    package.loaded[mod] = loaded
    package.preload[mod] = function()
      required = true
      return {}
    end
    vim.api.nvim_get_runtime_file = function(name, all)
      if name == "lua/nvim-treesitter/init.lua" then
        return on_rtp and { "/fake/lua/nvim-treesitter/init.lua" } or {}
      end
      return orig_rtf(name, all)
    end
    local ok, err = pcall(with_popup_stubs, nil, attached_noice, function(seen)
      body(seen, required)
    end)
    vim.api.nvim_get_runtime_file = orig_rtf
    package.loaded[mod] = orig_loaded
    package.preload[mod] = orig_preload
    if not ok then
      error(err, 0)
    end
  end

  -- 16: already loaded (by the user's config): ok, names the indentexpr.
  with_ts({}, false, function(seen, required)
    H.ok(find(seen, "ok", "nvim-treesitter loaded"), "nvim-treesitter: loaded -> ok")
    H.ok(find(seen, "ok", "only its indentexpr is used"), "nvim-treesitter: names indentexpr")
    H.ok(not required, "nvim-treesitter: loaded -> not required again")
  end)

  -- 17: installed but not loaded: reported, and the check does not load it.
  with_ts(nil, true, function(seen, required)
    H.ok(
      find(seen, "ok", "nvim-treesitter installed, not loaded yet"),
      "nvim-treesitter: on the rtp -> ok, not loaded"
    )
    H.ok(not required, "nvim-treesitter: the health check must not require() it")
    H.eq(package.loaded["nvim-treesitter"], nil, "nvim-treesitter: still unloaded after the check")
  end)

  -- 18: not installed: optional info, still without trying to require it.
  with_ts(nil, false, function(seen, required)
    H.ok(
      find(seen, "info", "nvim-treesitter not installed (optional; only its indentexpr"),
      "nvim-treesitter: missing -> info naming the indentexpr"
    )
    H.ok(not required, "nvim-treesitter: missing -> no require() attempt either")
  end)

  package.loaded["debugging.health"] = nil
end
