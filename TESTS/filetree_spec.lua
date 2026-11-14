-- TESTS/filetree_spec.lua
-- Covers `debugging.actions.filetree`: the three reports of `:Debug filetree`
-- against a stand-in for `require("filetree").fs_state()` (a table in
-- `package.loaded["filetree"]`; the shape is the one filetree.nvim documents
-- in docs/api.md, "The state of the file layer"), the degradation without
-- filetree.nvim, with one that has no `fs_state`, and with one whose
-- `fs_state` fails, and the routes of the command. Every action returns its
-- lines, so the reports are asserted on their text; `filetree.output =
-- "notify"` keeps the float out of the headless run.

return function(H)
  local orig_notify = vim.notify
  local seen = {}
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    seen[#seen + 1] = { msg = tostring(msg), level = level }
  end
  local function last()
    return seen[#seen] and seen[#seen].msg or ""
  end
  local function reset()
    seen = {}
  end
  local function joined(lines)
    return table.concat(lines or {}, "\n")
  end

  local saved_filetree = package.loaded["filetree"]

  ---The state of a tree that watches two roots on a platform with one handle per root.
  ---@return table
  local function busy_state()
    return {
      active = true,
      watch = true,
      recursive = true,
      watchers = {
        { dir = "C:/work/app", refs = 2 },
        { dir = "C:/work/notes", refs = 1, error = "EPERM: operation not permitted" },
      },
      released = { { dir = "C:/work/app/build", refs = 1 } },
      quarantined = { "C:/work/app/node_modules" },
      changed = { "C:/work/app/src" },
      reading = { "C:/work/notes/2026" },
      roots = { "C:/work/app", "C:/work/notes" },
      stats = { events = 1234, reports = 56, quarantined = 3 },
    }
  end

  local calls = 0
  ---@param state table|fun(): table
  local function stand_in(state)
    package.loaded["filetree"] = {
      fs_state = function()
        calls = calls + 1
        if type(state) == "function" then
          return state()
        end
        return state
      end,
    }
  end

  local ok, err = pcall(function()
    local config = require("debugging.config")
    config.setup({ filetree = { output = "notify" } })
    local filetree = require("debugging.actions.filetree")

    -- ================================================ without filetree.nvim
    -- Not loaded: said in one notification, and the plugin is not loaded to say it.
    package.loaded["filetree"] = nil
    local orig_preload = package.preload["filetree"]
    local required = 0
    package.preload["filetree"] = function()
      required = required + 1
      return { fs_state = busy_state }
    end
    for _, action in ipairs({ "watchers", "quarantine", "handles" }) do
      reset()
      H.eq(filetree[action](), nil, "filetree: " .. action .. " returns nil without filetree.nvim")
      H.match(last(), "filetree%.nvim is not loaded", "filetree: " .. action .. " says so")
      H.eq(seen[#seen].level, vim.log.levels.WARN, "filetree: ... as a warning")
    end
    H.eq(required, 0, "filetree: a report never loads filetree.nvim to ask it")
    H.eq(package.loaded["filetree"], nil, "filetree: ... and leaves it unloaded")
    package.preload["filetree"] = orig_preload

    -- A filetree.nvim from before the reading function.
    package.loaded["filetree"] = { setup = function() end }
    reset()
    H.eq(filetree.watchers(), nil, "filetree: an old filetree.nvim yields no report")
    H.match(last(), "has no fs_state%(%)", "filetree: ... and the message names what is missing")

    -- A reading function that raises, or answers with something that is no table.
    stand_in(function()
      error("watch table is gone")
    end)
    reset()
    H.eq(filetree.handles(), nil, "filetree: a failing fs_state yields no report")
    H.match(last(), "fs_state%(%) failed", "filetree: ... and is reported")
    H.match(last(), "watch table is gone", "filetree: ... with its reason")
    package.loaded["filetree"] = {
      fs_state = function()
        return "nope"
      end,
    }
    reset()
    H.eq(filetree.quarantine(), nil, "filetree: an answer that is no table yields no report")
    H.match(last(), "fs_state%(%) failed", "filetree: ... and is reported")

    -- ================================================ watchers
    stand_in(busy_state())
    calls = 0
    reset()
    local watchers = joined(filetree.watchers())
    H.eq(calls, 1, "watchers: the state is read once")
    H.match(watchers, "the own tree is the active backend", "watchers: says the backend is active")
    H.match(watchers, "one handle per root", "watchers: says how the tree watches")
    H.match(
      watchers,
      "1234 events, 56 reports, 3 quarantines",
      "watchers: the counters since Neovim started"
    )
    H.match(watchers, "watchers %(2%)", "watchers: counts the handles")
    H.match(watchers, "   2  C:/work/app\n", "watchers: a folder with its number of askers")
    H.match(
      watchers,
      "   1  C:/work/notes   ERROR: EPERM: operation not permitted",
      "watchers: a handle that failed carries its error"
    )
    H.match(watchers, "1 watcher%(s%) report an error", "watchers: ... and the failures are summed")
    H.eq(#seen, 1, "watchers: with output = notify the report is one notification")
    H.ok(last():find(watchers, 1, true) ~= nil, "watchers: ... that carries the whole report")
    H.eq(seen[#seen].level, vim.log.levels.INFO, "watchers: ... at info level")

    -- ================================================ quarantine
    reset()
    local quarantine = joined(filetree.quarantine())
    H.match(quarantine, "3 folder%(s%) quarantined since Neovim started", "quarantine: the counter")
    H.match(quarantine, "quarantined %(1%)", "quarantine: counts what is held back now")
    H.match(quarantine, "  C:/work/app/node_modules", "quarantine: names the folder")
    H.match(quarantine, "changed %(1%)", "quarantine: counts the unreported changes")
    H.match(quarantine, "  C:/work/app/src", "quarantine: names the changed folder")
    H.match(quarantine, "reading %(1%)", "quarantine: counts the pending reads")
    H.match(quarantine, "  C:/work/notes/2026", "quarantine: names the folder being read")

    -- ================================================ handles
    reset()
    local handles = joined(filetree.handles())
    H.match(handles, "roots %(2%)", "handles: counts the roots")
    H.match(handles, "open handles %(2%)", "handles: counts the open handles")
    H.match(handles, "   2  C:/work/app\n", "handles: a handle with its askers")
    H.match(handles, "released %(1%)", "handles: counts the released handles")
    H.match(handles, "   1  C:/work/app/build", "handles: names a released one")
    H.match(
      handles,
      "covered   every folder listed under open handles and everything below it",
      "handles: one handle per root covers what lies below"
    )

    -- one handle per folder read: what lies below a listed folder is not covered
    local per_folder = busy_state()
    per_folder.recursive = false
    stand_in(per_folder)
    handles = joined(filetree.handles())
    H.match(handles, "one handle per folder read", "handles: says the per-folder mode")
    H.match(handles, "not what lies below them", "handles: ... and what it covers")

    -- ================================================ a tree that holds nothing
    stand_in({
      active = true,
      watch = false,
      recursive = false,
      watchers = {},
      released = {},
      quarantined = {},
      changed = {},
      reading = {},
      roots = {},
      stats = { events = 0, reports = 0, quarantined = 0 },
    })
    watchers = joined(filetree.watchers())
    H.match(watchers, "watch     off %(native%.watch = false%)", "idle: watch = false is said")
    H.match(watchers, "watchers %(0%)", "idle: no watcher is counted")
    H.match(watchers, "\n  none", "idle: ... and the list says none")
    H.ok(not watchers:find("report an error", 1, true), "idle: no failure line without failures")
    quarantine = joined(filetree.quarantine())
    H.match(quarantine, "quarantined %(0%)", "idle: nothing is quarantined")
    handles = joined(filetree.handles())
    H.match(
      handles,
      "none: this Neovim holds no folder open for the tree",
      "idle: handles says that nothing is held"
    )
    H.match(handles, "covered   no folder", "idle: ... and that nothing is covered")

    -- ================================================ not the active backend
    local inactive = busy_state()
    inactive.active = false
    stand_in(inactive)
    for _, action in ipairs({ "watchers", "quarantine", "handles" }) do
      local text = joined(filetree[action]())
      H.match(
        text,
        "the own tree is NOT the active backend",
        "inactive: " .. action .. " says that the own tree is not the backend"
      )
      H.ok(
        not text:find("is the active backend", 1, true),
        "inactive: " .. action .. " does not claim it is"
      )
    end
    H.match(
      joined(filetree.watchers()),
      "   2  C:/work/app\n",
      "inactive: what an earlier tree left open is still listed"
    )

    -- ================================================ a state with fields missing
    -- A version that does not have a field yet: an empty list, not an error.
    stand_in({ active = true })
    H.match(joined(filetree.watchers()), "watchers %(0%)", "sparse: watchers reads as empty")
    H.match(joined(filetree.watchers()), "0 events, 0 reports", "sparse: the counters read as 0")
    H.match(joined(filetree.quarantine()), "reading %(0%)", "sparse: quarantine reads as empty")
    H.match(joined(filetree.handles()), "roots %(0%)", "sparse: handles reads as empty")
    stand_in({ active = true, watchers = { {} } })
    H.match(joined(filetree.watchers()), "   %?  %?", "sparse: an entry without fields shows as ?")
    -- an entry that is no table (a version that lists plain folders): shown, not raised on
    stand_in({ active = true, watchers = { "C:/plain", 7 }, released = { "C:/gone" } })
    local plain_ok, plain = pcall(filetree.watchers)
    H.ok(plain_ok, "sparse: an entry that is no table does not raise: " .. tostring(plain))
    H.match(joined(plain), "   %?  C:/plain", "sparse: ... it is shown as the folder")
    H.match(joined(plain), "   %?  7", "sparse: ... whatever it is")
    H.match(joined(filetree.handles()), "   %?  C:/gone", "sparse: the same for a released one")

    -- ================================================ the command
    stand_in(busy_state())
    local commands = require("debugging.commands")
    H.eq(config.get().features.filetree, true, "command: the category is on by default")
    H.eq_list(
      commands.complete("", "Debug filetree ", 15),
      { "watchers", "quarantine", "handles" },
      "command: the three reports complete"
    )
    H.ok(
      vim.tbl_contains(commands.complete("", "Debug f", 7), "filetree"),
      "command: the category completes"
    )
    for _, action in ipairs({ "watchers", "quarantine", "handles" }) do
      calls = 0
      reset()
      commands.dispatch({ "filetree", action })
      H.eq(calls, 1, "command: `filetree " .. action .. "` reads the state")
      H.match(last(), "backend   the own tree", "command: ... and prints the report")
    end
    H.match(last(), "open handles %(2%)", "command: the last one was the handles report")

    config.setup({ features = { filetree = false } })
    H.ok(
      not vim.tbl_contains(commands.complete("", "Debug f", 7), "filetree"),
      "command: features.filetree = false takes the category out"
    )
  end)

  package.loaded["filetree"] = saved_filetree
  require("debugging.config").setup({})
  vim.notify = orig_notify
  if not ok then
    error(err, 0)
  end
end
