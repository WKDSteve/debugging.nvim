---@module 'debugging.actions.filetree'
--- `:Debug filetree watchers|quarantine|handles` -- what does the own tree of
--- filetree.nvim hold on the disk right now?
---
--- Three read-only reports over one function, `require("filetree").fs_state()`
--- (filetree.nvim docs/api.md, "The state of the file layer"):
---
---   watchers    the open `fs_event` handles with the number of askers per
---               folder, how the tree watches (one handle per root, or one per
---               folder read) and the event counters
---   quarantine  folders held back after an event storm, folders with a change
---               that is not reported yet, folders being read
---   handles     everything this Neovim keeps open below the roots: the open
---               handles, the ones released for a running file operation, and
---               which folders a handle covers -- the question behind "who
---               keeps this folder busy?"
---
--- Nothing is started and nothing is changed: filetree.nvim is not even loaded
--- for it. A session that has not loaded filetree.nvim holds nothing, and a
--- report that loaded the plugin to say so would change what it reports on.
--- Every report says when the own tree is not the active backend.
---
--- Output goes to a scratch float (`filetree.output = "float"`) or, when no
--- window can be opened or the option says so, to one notification. Every
--- action also returns its lines, which is what the spec reads.

local notify = require("lib.nvim.notify").create("[debugging.actions.filetree]")
local window = require("lib.nvim.window")
local config = require("debugging.config")

local M = {}

-- ---------------------------------------------------------------- helpers

---@internal
---@return Dbg.Config.Filetree
local function cfg()
  return config.get().filetree or {}
end

---@internal
---The state of the file layer, or nil after a notification that says why
---there is none to show.
---@return table|nil state
local function read_state()
  local filetree = package.loaded["filetree"]
  if type(filetree) ~= "table" then
    notify.warn(
      "filetree.nvim is not loaded in this session (not installed, or not used yet): it holds nothing"
    )
    return nil
  end
  if type(filetree.fs_state) ~= "function" then
    notify.error(
      "this filetree.nvim has no fs_state() -- update it (docs/api.md, 'The state of the file layer')"
    )
    return nil
  end
  local ok, state = pcall(filetree.fs_state)
  if not ok or type(state) ~= "table" then
    notify.error(("filetree.fs_state() failed: %s"):format(tostring(state)))
    return nil
  end
  return state
end

---@internal
---A list field of the state; anything else (a field a version does not have)
---reads as empty.
---@param value any
---@return table[]
local function list(value)
  return type(value) == "table" and value or {}
end

---@internal
---Render a report: scratch float when configured and possible, one
---notification otherwise. Returns the lines either way.
---@param title string
---@param lines string[]
---@return string[]
local function render(title, lines)
  if cfg().output ~= "notify" then
    local ok, winid = pcall(window.make_scratch, {
      lines = lines,
      filetype = "debugging-filetree",
      title = (" :%s filetree %s "):format(config.get().command, title),
      title_pos = "center",
      nice_quit = { force = true },
      wo = { cursorline = true },
    })
    if ok and winid then
      return lines
    end
  end
  notify.info(table.concat(lines, "\n"))
  return lines
end

---@internal
---The lines every report starts with: is this the active backend, does the
---tree watch at all, and how.
---@param state table
---@return string[]
local function header(state)
  local lines = {}
  if state.active == true then
    lines[#lines + 1] = 'backend   the own tree is the active backend (adapter = "native")'
  else
    lines[#lines + 1] = "backend   the own tree is NOT the active backend:"
    lines[#lines + 1] =
      "          what is listed below was left by a tree opened before the backend changed"
  end
  if state.watch == false then
    lines[#lines + 1] =
      "watch     off (native.watch = false): the tree does not follow the disk and holds no handle"
  elseif state.recursive == true then
    lines[#lines + 1] = "watch     one handle per root, watching everything below it"
  else
    lines[#lines + 1] = "watch     one handle per folder read"
  end
  return lines
end

---@internal
---One line per entry of a `{ dir, refs, error? }` list, or one line saying
---that there is none.
---@param lines string[]
---@param entries table[]
---@param none string
---@return nil
local function add_handles(lines, entries, none)
  if #entries == 0 then
    lines[#lines + 1] = "  " .. none
    return
  end
  for _, entry in ipairs(entries) do
    local line = ("  %4s  %s"):format(tostring(entry.refs or "?"), tostring(entry.dir or "?"))
    if entry.error ~= nil then
      line = line .. "   ERROR: " .. tostring(entry.error)
    end
    lines[#lines + 1] = line
  end
end

---@internal
---One line per folder, or one line saying that there is none.
---@param lines string[]
---@param dirs any[]
---@param none string
---@return nil
local function add_dirs(lines, dirs, none)
  if #dirs == 0 then
    lines[#lines + 1] = "  " .. none
    return
  end
  for _, dir in ipairs(dirs) do
    lines[#lines + 1] = "  " .. tostring(dir)
  end
end

-- ---------------------------------------------------------------- actions

---The open `fs_event` handles with their askers, how the tree watches, and
---the counters since Neovim started.
---@return string[]|nil lines  nil when there is no state to read
function M.watchers()
  local state = read_state()
  if not state then
    return nil
  end
  local watchers = list(state.watchers)
  local stats = type(state.stats) == "table" and state.stats or {}
  local lines = header(state)
  lines[#lines + 1] = ("events    %s events, %s reports, %s quarantines since Neovim started"):format(
    tostring(stats.events or 0),
    tostring(stats.reports or 0),
    tostring(stats.quarantined or 0)
  )
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("watchers (%d)   refs  folder"):format(#watchers)
  add_handles(lines, watchers, "none")
  local failed = 0
  for _, entry in ipairs(watchers) do
    if entry.error ~= nil then
      failed = failed + 1
    end
  end
  if failed > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("%d watcher(s) report an error: those folders are not followed"):format(
      failed
    )
  end
  return render("watchers", lines)
end

---Folders held back after an event storm, folders with a change that is not
---reported yet, and folders being read.
---@return string[]|nil lines  nil when there is no state to read
function M.quarantine()
  local state = read_state()
  if not state then
    return nil
  end
  local quarantined, changed, reading =
    list(state.quarantined), list(state.changed), list(state.reading)
  local stats = type(state.stats) == "table" and state.stats or {}
  local lines = header(state)
  lines[#lines + 1] = ("storms    %s folder(s) quarantined since Neovim started"):format(
    tostring(stats.quarantined or 0)
  )
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("quarantined (%d): held back after an event storm, reported once quiet"):format(
    #quarantined
  )
  add_dirs(lines, quarantined, "none")
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("changed (%d): a listing changed and is not reported yet"):format(#changed)
  add_dirs(lines, changed, "none")
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("reading (%d): being read right now"):format(#reading)
  add_dirs(lines, reading, "none")
  return render("quarantine", lines)
end

---Everything this Neovim keeps open below the roots of its trees: the open
---handles, the ones released for a running file operation, and which folders
---a handle covers.
---@return string[]|nil lines  nil when there is no state to read
function M.handles()
  local state = read_state()
  if not state then
    return nil
  end
  local watchers, released, roots = list(state.watchers), list(state.released), list(state.roots)
  local lines = header(state)
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("roots (%d): the trees there are, one per tab that opened one"):format(
    #roots
  )
  add_dirs(lines, roots, "none")
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("open handles (%d)   refs  folder"):format(#watchers)
  add_handles(lines, watchers, "none: this Neovim holds no folder open for the tree")
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("released (%d): closed for a running file operation, opened again after it"):format(
    #released
  )
  add_handles(lines, released, "none")
  lines[#lines + 1] = ""
  if #watchers == 0 then
    lines[#lines + 1] =
      "covered   no folder: a folder that is busy is not kept by the tree of this Neovim"
  elseif state.recursive == true then
    lines[#lines + 1] = "covered   every folder listed under open handles and everything below it"
  else
    lines[#lines + 1] = "covered   the folders listed under open handles, not what lies below them"
  end
  return render("handles", lines)
end

return M
