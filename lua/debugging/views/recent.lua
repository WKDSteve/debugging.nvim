---@module 'debugging.views.recent'
--- Thin dispatcher behind `<m`/`<n`/`<e` (messages/all/errors): pulls data
--- from `lib.nvim.messages`, renders it via `ui.kit.message_log` (a live,
--- paginated, collapsible popup) when ui.nvim is installed, falls back to a
--- static `lib.nvim.output.viewer` dump otherwise. Each store entry reaches the
--- popup as a header line (time, tag, title) over its full text wrapped to
--- `views.recent.wrap_width`, which the popup folds. Owns no window-tracking
--- of its own beyond `lib.nvim.window.tag` -- the same primitive
--- `debugging.views.display` uses to find and close these windows.

local window_tag = require("lib.nvim.window").tag
local notify = require("lib.nvim.notify").create("[debugging.views.recent]")

local M = {}

local NON_ERROR_LEVELS = {
  vim.log.levels.TRACE,
  vim.log.levels.DEBUG,
  vim.log.levels.INFO,
  vim.log.levels.WARN,
}

---@type table<string, integer[]|nil>
local FILTER_LEVELS = {
  all = nil,
  non_error = NON_ERROR_LEVELS,
  error = { vim.log.levels.ERROR },
}

local FILTER_TAG = {
  all = "recent_all",
  non_error = "recent_messages",
  error = "recent_errors",
}

local FILTER_TITLE = {
  all = "Recent messages (all)",
  non_error = "Recent messages",
  error = "Recent errors",
}

---@internal
---@param levels integer[]|nil
---@param level integer
---@return boolean
local function level_matches(levels, level)
  if not levels then
    return true
  end
  for _, l in ipairs(levels) do
    if l == level then
      return true
    end
  end
  return false
end

---Render one entry as display lines. `content` may hold embedded newlines
---(error texts, stack traces), which the viewer rejects, so split it; only
---the first line carries the age prefix, the rest is indented under it.
---@internal
---@param entry table
---@return string[]
local function fallback_lines(entry)
  local delta_s = math.max(0, (vim.uv.hrtime() / 1e6 - (entry.time_ms or 0)) / 1000)
  local prefix = ("[%ds ago] "):format(math.floor(delta_s))
  local parts = vim.split(tostring(entry.content or ""), "\r?\n")
  while #parts > 1 and parts[#parts] == "" do
    parts[#parts] = nil
  end
  local indent = (" "):rep(#prefix)
  local out = {}
  for i, part in ipairs(parts) do
    -- A stray CR (progress output that redraws a line) would render as ^M.
    out[i] = (i == 1 and prefix or indent) .. part:gsub("\r", "")
  end
  return out
end

-- `kind`s that say nothing beyond "a message": left out of the tag.
local PLAIN_KINDS = { [""] = true, notify = true, echo = true, echomsg = true, echoerr = true }

local LEVEL_NAME = {
  [vim.log.levels.WARN] = "WARN",
  [vim.log.levels.ERROR] = "ERROR",
}

-- Cells the kit draws in front of an entry's first line: fold mark, "[HH:MM:SS Ns ago] ".
local HEADER_PREFIX_W = 24

---@internal
---Cells of the "  … (+N more lines)" marker the kit appends to a folded entry with `n` hidden lines.
---@param n integer
---@return integer
local function suffix_width(n)
  if n == 0 then
    return 0
  end
  return vim.fn.strdisplaywidth(("  … (+%d more line%s)"):format(n, n == 1 and "" or "s"))
end

---@internal
---Text width the popup wraps message bodies to.
---@return integer
local function wrap_width()
  local cfg = require("debugging.views").get_recent_config()
  local w = tonumber(cfg.wrap_width) or math.min(100, vim.o.columns - 12)
  return math.max(30, math.floor(w))
end

---@internal
---The lines of a message as they are shown: CRLF split, a lone CR (a progress line redrawing
---itself) keeps only what follows it, trailing empty lines dropped.
---@param text string
---@return string[]
local function text_lines(text)
  local lines = vim.split(text, "\n", { plain = true })
  for i, line in ipairs(lines) do
    if line:find("\r", 1, true) then
      lines[i] = line:gsub("\r+$", ""):match("[^\r]*$")
    end
  end
  while #lines > 1 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  return lines
end

---@internal
---First `width` display cells of `s` (character-safe).
---@param s string
---@param width integer
---@return string
local function take_cells(s, width)
  local nchars = vim.fn.strchars(s)
  local lo, hi = 0, nchars
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if vim.fn.strdisplaywidth(vim.fn.strcharpart(s, 0, mid)) <= width then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return vim.fn.strcharpart(s, 0, math.max(1, lo))
end

---Word-wrap one line to `width` display cells; words longer than a line are cut hard.
---Continuation rows are indented by two spaces so they read apart from real line breaks.
---@param line string
---@param width integer
---@return string[]
function M.wrap_line(line, width)
  local out = {}
  local indent = ""
  local pos, len = 1, #line
  while true do
    local avail = math.max(1, width - #indent)
    -- Only the next `avail + 1` characters can matter for this row (a character is at least
    -- one cell, and at most 4 bytes): measuring the whole rest per row made a 64 KB line
    -- (merged `:!cmd` output) take about a second.
    local chunk = vim.fn.strcharpart(line:sub(pos, pos + (avail + 1) * 4 - 1), 0, avail + 1)
    if pos + #chunk > len and vim.fn.strdisplaywidth(chunk) <= avail then
      out[#out + 1] = indent .. chunk:gsub("%s+$", "")
      return out
    end
    local head = take_cells(chunk, avail)
    -- Break at the last blank inside the row, if there is one past its first quarter.
    local cut = head:match("^.*()%s")
    if cut and cut > math.floor(#head / 4) and cut <= #head then
      head = head:sub(1, cut - 1)
    end
    out[#out + 1] = indent .. head:gsub("%s+$", "")
    pos = line:find("%S", pos + #head) or len + 1
    indent = "  "
    if pos > len then
      return out
    end
  end
end

---The tag of a message: level (WARN/ERROR), Vim error code (`E492`), kind and source.
---@param entry table  # a `lib.nvim.messages` entry
---@return string  # "" when there is nothing to say
function M.entry_tag(entry)
  local parts = {}
  local level = LEVEL_NAME[entry.level]
  if level then
    parts[#parts + 1] = level
  end
  local text = tostring(entry.content or "")
  local code = text:match("%f[%w](E%d+):")
  if code then
    parts[#parts + 1] = code
  end
  local kind = entry.kind
  if type(kind) == "string" and not PLAIN_KINDS[kind] then
    parts[#parts + 1] = kind
  end
  local source = type(entry.source) == "string" and vim.trim(entry.source) or ""
  local name = (source:gsub("^%[(.*)%]$", "%1"))
  -- A notify prefix the text already starts with would only be said twice; `lib.nvim.notify`
  -- passes the bare name as source and puts "[name]" in front of the text.
  local bracketed = "[" .. name .. "]"
  if name ~= "" and text:sub(1, #name) ~= name and text:sub(1, #bracketed) ~= bracketed then
    parts[#parts + 1] = name
  end
  return table.concat(parts, " ")
end

---What the popup shows for one message: a header line (tag + title, the title cut to fit the
---window) and, when the header does not hold the whole message, the full text wrapped to
---`width` below it -- the part `<CR>` folds and unfolds. Short one-line messages stay one line.
---@param entry table  # a `lib.nvim.messages` entry
---@param width integer
---@return string
function M.format_content(entry, width)
  local lines = text_lines(tostring(entry.content or ""):gsub("%z", "\u{FFFD}"))
  local first_idx = 1
  while first_idx < #lines and vim.trim(lines[first_idx]) == "" do
    first_idx = first_idx + 1
  end
  local title = vim.trim(lines[first_idx] or "")
  local tag = M.entry_tag(entry)
  local prefix = tag ~= "" and ("[" .. tag .. "] ") or ""
  -- The header row must fit the window the kit can open (at most `columns - 4`), not only the
  -- wrap width, or it wraps onto a second screen line and pushes the last entry out of view.
  local room = math.min(width, vim.o.columns - 4) - HEADER_PREFIX_W - vim.fn.strdisplaywidth(prefix)

  local rest = {}
  for i = first_idx + 1, #lines do
    vim.list_extend(rest, M.wrap_line(lines[i], width))
  end
  local title_w = vim.fn.strdisplaywidth(title)
  local cut = title_w > room - suffix_width(#rest)
  local body = rest
  if cut then
    body = M.wrap_line(lines[first_idx], width)
    vim.list_extend(body, rest)
    -- A character is at least one cell: the first `room` characters are enough to cut from.
    local keep = math.max(9, room - suffix_width(#body)) - 1
    title = take_cells(vim.fn.strcharpart(title, 0, keep + 1), keep) .. "…"
  end
  local out = { prefix .. title }
  vim.list_extend(out, body)
  return table.concat(out, "\n")
end

---Wall-clock time of an entry ("HH:MM:SS Ns ago"); `time_ms` is the monotonic
---`vim.uv.hrtime()` clock of `lib.nvim.messages`, `now_ms` the same clock.
---@param entry table
---@param now_ms number
---@return string
function M.format_time(entry, now_ms)
  local time_ms = entry.time_ms or now_ms
  local sec, usec = vim.uv.gettimeofday()
  local wall_now_ms = sec * 1000 + usec / 1000
  local wall_s = math.floor((wall_now_ms - (now_ms - time_ms)) / 1000)
  local age_s = math.max(0, math.floor((now_ms - time_ms) / 1000))
  local age = age_s < 60 and ("%ds"):format(age_s)
    or age_s < 3600 and ("%dm"):format(math.floor(age_s / 60))
    or ("%dh"):format(math.floor(age_s / 3600))
  return ("%s %s ago"):format(os.date("%H:%M:%S", wall_s), age)
end

---A popup entry for a store entry: `content` is formatted on read (cached while text and
---width stay the same), everything else is the store entry's own -- a `:!cmd` entry that
---grows in place after it was shown shows the new output on the next redraw.
---@param raw table  # a `lib.nvim.messages` entry
---@return table
function M.display_entry(raw)
  local src, w, out
  return setmetatable({ raw = raw }, {
    __index = function(_, key)
      if key ~= "content" then
        return raw[key]
      end
      local width = wrap_width()
      if raw.content ~= src or width ~= w then
        src, w = raw.content, width
        out = M.format_content(raw, width)
      end
      return out
    end,
  })
end

---@internal
---@param list table[]
---@return table[]
local function display_entries(list)
  local out = {}
  for i, raw in ipairs(list) do
    out[i] = M.display_entry(raw)
  end
  return out
end

---Open (or focus, if already open) the recent-messages popup for `filter`.
---@param filter "all"|"non_error"|"error"
---@return nil
function M.show(filter)
  local tag = FILTER_TAG[filter]
  if not tag then
    notify.warn(("recent view: unknown filter %q"):format(tostring(filter)))
    return
  end

  local existing_win = window_tag.find(tag)
  if existing_win then
    vim.api.nvim_set_current_win(existing_win)
    return
  end

  local cfg = require("debugging.views").get_recent_config()
  local messages = require("lib.nvim.messages")
  local levels = FILTER_LEVELS[filter]
  local window_s = cfg.window_s or 10

  local ok_kit, kit = pcall(require, "ui.kit")
  local has_kit = ok_kit and type(kit.message_log) == "function"

  -- Subscribe BEFORE the snapshot: whatever is stored while the popup is being built (an
  -- autocmd that fires when the float opens, say) would otherwise be in neither. Entries
  -- park in `pending` until the handle exists; the ones the snapshot already holds are dropped.
  local handle
  local pending = {}
  local subscription
  if has_kit then
    subscription = messages.on_message(function(entry)
      if not level_matches(levels, entry.level) then
        return
      end
      if handle then
        handle:append({ M.display_entry(entry) })
      else
        pending[#pending + 1] = entry
      end
    end)
  end

  local loaded_since_ms = (vim.uv.hrtime() / 1e6) - (window_s * 1000)
  local entries = messages.snapshot({ since_ms = loaded_since_ms, levels = levels })
  -- A quiet minute must not open an empty popup (the command that was just run is
  -- "not in there"): top up to the newest `min_entries`, however old, and page from there.
  local min_entries = cfg.min_entries or 5
  if #entries < min_entries then
    local all = messages.snapshot({ levels = levels })
    if #all > #entries then
      entries = vim.list_slice(all, math.max(1, #all - min_entries + 1))
      loaded_since_ms = entries[1].time_ms
    end
  end

  if not has_kit then
    local lines = {}
    for _, entry in ipairs(entries) do
      vim.list_extend(lines, fallback_lines(entry))
    end
    if #lines == 0 then
      lines = { "(no messages)" }
    end
    -- height floored at 2: lib.nvim.window.tag.find() requires height > 1
    -- strictly, and a sparse snapshot (0-1 entries -- the common case for
    -- the error filter) would otherwise open a legitimate but invisible-to-
    -- find() 1-row window, silently defeating both the reuse check above
    -- and display.clear_all()'s <x> cleanup.
    local surf = require("lib.nvim.output.viewer").show_lines(FILTER_TITLE[filter], lines, {
      height = math.max(2, #lines),
    })
    if surf then
      window_tag.set(surf.winid, tag, surf.bufnr)
    end
    notify.info("ui.nvim not installed -- showing a static snapshot, no live updates/pagination")
    return
  end

  -- The cursor before each loaded page, so `-` can hand the page back and `+` loads it again.
  ---@type number[]
  local page_bounds = {}

  ---Everything older than what is loaded so far, oldest first.
  ---@return table[]
  local function older_than_loaded()
    return messages.snapshot({ until_ms = loaded_since_ms - 0.001, levels = levels })
  end

  handle = kit.message_log({
    title = FILTER_TITLE[filter],
    entries = display_entries(entries),
    format_entry_time = M.format_time,
    order = cfg.order or "newest_last",
    collapsed_default = cfg.collapsed_default ~= false,
    -- No "more above" hint when the ring holds nothing older to begin with.
    has_more_older = #older_than_loaded() > 0,
    load_more = function(direction)
      if direction ~= "older" then
        return {}
      end
      -- An empty return tells the popup there is nothing left, for good. A quiet
      -- stretch longer than `window_s` between two messages must therefore not
      -- end the paging: skip the gap, so the page is one `window_s` ending at
      -- the newest older entry.
      local older_all = older_than_loaded()
      if #older_all == 0 then
        return {}
      end
      local newest_older_ms = older_all[#older_all].time_ms
      local new_since = loaded_since_ms - window_s * 1000
      if newest_older_ms < new_since then
        new_since = newest_older_ms - window_s * 1000
      end
      local older = messages.snapshot({
        since_ms = new_since,
        until_ms = loaded_since_ms - 0.001,
        levels = levels,
      })
      page_bounds[#page_bounds + 1] = loaded_since_ms
      loaded_since_ms = new_since
      return display_entries(older)
    end,
    on_unload = function()
      loaded_since_ms = table.remove(page_bounds) or loaded_since_ms
    end,
  })
  if not handle then
    messages.off_message(subscription)
    return
  end

  window_tag.set(handle.surf.winid, tag, handle.surf.bufnr)
  handle:on_close(function()
    messages.off_message(subscription)
  end)

  -- What arrived while the popup was being built, minus what the snapshot already had.
  local have = {}
  for _, e in ipairs(entries) do
    have[("%s|%s"):format(e.time_ms, e.content)] = true
  end
  local late = {}
  for _, e in ipairs(pending) do
    if not have[("%s|%s"):format(e.time_ms, e.content)] then
      late[#late + 1] = e
    end
  end
  pending = {}
  if #late > 0 then
    handle:append(display_entries(late))
  end
end

return M
