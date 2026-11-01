---@module 'debugging.views.capture'
--- Unified capture system for :messages, Noice, etc.
---
--- Reads the message history (Noice when available, `:messages` otherwise),
--- then optionally copies it to the clipboard and writes a timestamped file
--- under the configured output directory. Clipboard and file writer are
--- pulled in lazily, so a capture that needs neither costs nothing.
--- Returns `ok, content_or_error` — it never notifies on behalf of callers.

local notify = require("lib.nvim.notify").create("[debugging.views.capture]")

local lazy = require("lib.lua.lazy")
local copy_to_clipboard = lazy.require("debugging.views.capture.clipboard")
local write_file = lazy.require("lib.nvim.fs.write.to_file")

local M = {}

---@type string  Default capture directory: dumps are debug state, not files of the user's config repository
M.base_dir = vim.fn.stdpath("state") .. "/debug_views"

---@internal
---@param s string
---@return string
local function rstrip(s)
  return (s:gsub("%s*$", ""))
end

---@internal
---@return string dir, string logfile
local function resolve_paths()
  local base = require("lib.nvim.normalize").normalize_path(M.base_dir)
  local dir = base
  local timestamp = os.date("%Y%m%d-%H%M%S")
  local logfile =
    require("lib.nvim.fs.path").joinpath({ dir, string.format("messages-%s.log", timestamp) })
  return dir, logfile
end

---@internal
---Extract text content from Noice message object (handles functions and _lines)
---@param obj any Noice message object or content part
---@param depth? integer Recursion depth limit
---@return string|nil
local function extract_noice_text(obj, depth)
  depth = depth or 0
  if depth > 10 then
    return nil
  end

  if type(obj) == "string" then
    return obj
  end

  if type(obj) ~= "table" then
    return nil -- Don't stringify non-string, non-table values
  end

  -- Noice Message objects have _lines field (internal storage)
  if obj._lines and type(obj._lines) == "table" then
    local lines = {}
    for _, line in ipairs(obj._lines) do
      if type(line) == "table" then
        -- Each line is an array of content parts
        local parts = {}
        for _, part in ipairs(line) do
          if type(part) == "string" then
            parts[#parts + 1] = part
          elseif type(part) == "table" then
            -- Part might have _text field
            if part._text then
              parts[#parts + 1] = tostring(part._text)
            elseif part[1] then
              parts[#parts + 1] = tostring(part[1])
            end
          end
        end
        if #parts > 0 then
          lines[#lines + 1] = table.concat(parts, "")
        end
      elseif type(line) == "string" then
        lines[#lines + 1] = line
      end
    end
    if #lines > 0 then
      return table.concat(lines, "\n")
    end
  end

  -- If content is a function, call it
  if obj.content and type(obj.content) == "function" then
    local ok, result = pcall(obj.content, obj)
    if ok and result then
      return extract_noice_text(result, depth + 1)
    end
  end

  -- If content is already extracted
  if obj.content and type(obj.content) ~= "function" then
    return extract_noice_text(obj.content, depth + 1)
  end

  -- Handle array of content parts
  if obj[1] ~= nil then
    local parts = {}
    for _, item in ipairs(obj) do
      if type(item) == "string" then
        parts[#parts + 1] = item
      elseif type(item) == "table" then
        if item._text then
          parts[#parts + 1] = tostring(item._text)
        elseif item[1] then
          local nested = extract_noice_text(item, depth + 1)
          if nested then
            parts[#parts + 1] = nested
          end
        else
          local text = item.text or item.str
          if text then
            parts[#parts + 1] = tostring(text)
          end
        end
      end
    end
    if #parts > 0 then
      return table.concat(parts, "")
    end
  end

  -- Try other known fields
  if obj._text then
    return tostring(obj._text)
  end

  if obj.message then
    if type(obj.message) == "string" then
      return obj.message
    else
      return extract_noice_text(obj.message, depth + 1)
    end
  end

  if obj.text then
    return tostring(obj.text)
  end

  if obj.str then
    return tostring(obj.str)
  end

  return nil
end

---@internal
---Try to get messages from Noice if available
---@return boolean success, string|nil messages, string|nil source
local function try_noice()
  local ok_noice, noice = pcall(require, "noice")
  if not ok_noice then
    return false, nil, "noice not installed"
  end

  -- Method 1: Get from message manager (most reliable)
  local ok_manager, manager = pcall(require, "noice.message.manager")
  if ok_manager and manager and manager.get then
    -- Get ALL messages including history
    local ok_msgs, messages = pcall(manager.get, nil, {
      history = true,
      reverse = false, -- Chronological order
    })

    if ok_msgs and messages and type(messages) == "table" then
      local lines = {}
      local msg_count = 0

      for _, msg in ipairs(messages) do
        msg_count = msg_count + 1
        local text = extract_noice_text(msg)

        if text and text ~= "" then
          -- Include timestamp if available
          if msg.opts and msg.opts.timestamp then
            local ts = os.date("%H:%M:%S", msg.opts.timestamp)
            lines[#lines + 1] = string.format("[%s] %s", ts, text)
          else
            lines[#lines + 1] = text
          end
        end
      end

      if #lines > 0 then
        return true,
          table.concat(lines, "\n"),
          string.format("noice.manager (%d messages)", msg_count)
      end
    end
  end

  -- Method 2: Try getting from Noice history directly
  if noice.history and type(noice.history.get) == "function" then
    local ok_hist, history = pcall(noice.history.get)
    if ok_hist and history and type(history) == "table" and #history > 0 then
      local lines = {}
      for _, entry in ipairs(history) do
        local text = extract_noice_text(entry)
        if text and text ~= "" then
          lines[#lines + 1] = text
        end
      end
      if #lines > 0 then
        return true,
          table.concat(lines, "\n"),
          string.format("noice.history (%d entries)", #history)
      end
    end
  end

  -- Method 3: Read from Noice buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ok_name, name = pcall(vim.api.nvim_buf_get_name, buf)
      if ok_name and name and name:match("noice://") then
        local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
        if ok_lines and lines and #lines > 0 then
          local filtered = {}
          for _, line in ipairs(lines) do
            if line ~= "" then
              filtered[#filtered + 1] = line
            end
          end
          if #filtered > 0 then
            return true,
              table.concat(filtered, "\n"),
              string.format("noice buffer (%d lines)", #filtered)
          end
        end
      end
    end
  end

  -- Method 4: Try API status (usually just shows last message)
  if noice.api and noice.api.status and noice.api.status.message then
    -- noice.api.status is a metatable-factory module (__index builds a
    -- NoiceStatus per key at runtime) -- get() is real, LuaLS just cannot
    -- see through it. Already pcall-guarded either way.
    ---@diagnostic disable-next-line: undefined-field
    local ok_status, status_msg = pcall(noice.api.status.message.get)
    if ok_status and status_msg and status_msg ~= "" then
      return true, status_msg, "noice.api.status (last message only)"
    end
  end

  return false, nil, "noice available but empty"
end

---@internal
---Try to get messages via vim.fn.execute
---@return boolean success, string|nil messages, string|nil source
---@return boolean errored  True when the pcall itself threw (as opposed to a
--- legitimately empty `:messages` history).
local function try_execute()
  local ok_exec, messages = pcall(vim.fn.execute, "messages")
  if not ok_exec then
    return false, nil, "vim.fn.execute threw: " .. tostring(messages), true
  end
  if messages and rstrip(messages) ~= "" then
    return true, messages, "vim.fn.execute('messages')", false
  end
  return false, nil, "vim.fn.execute returned empty", false
end

---@internal
---Try to get messages via nvim_exec2
---@return boolean success, string|nil messages, string|nil source
---@return boolean errored  True when the pcall itself threw (as opposed to a
--- legitimately empty `:messages` history).
local function try_exec2()
  local ok_exec, res = pcall(vim.api.nvim_exec2, "messages", { output = true })
  if not ok_exec then
    return false, nil, "nvim_exec2 threw: " .. tostring(res), true
  end
  if res and res.output and rstrip(res.output) ~= "" then
    return true, res.output, "nvim_exec2('messages')", false
  end
  return false, nil, "nvim_exec2 returned empty", false
end

---@internal
---The capture strategies in the order they are tried.
---@type { name: string, fn: fun(): boolean, string|nil, string|nil, boolean|nil }[]
local STRATEGIES = {
  { name = "noice", fn = try_noice },
  { name = "execute", fn = try_execute },
  { name = "exec2", fn = try_exec2 },
}

---@internal
---Capture messages with multiple fallback strategies
---@param debug boolean
---@return boolean success, string|nil messages, string|nil source
local function capture_messages_raw(debug)
  local attempts = {}
  local any_errored = false

  -- Ordered fallback chain: Noice first (most reliable with Noice installed), then vim.fn.execute, then
  -- nvim_exec2. A strategy returns ok, messages, source and - when it can throw - a fourth "errored" flag.
  for _, strategy in ipairs(STRATEGIES) do
    local ok, msgs, src, errored = strategy.fn()
    any_errored = any_errored or errored == true
    attempts[#attempts + 1] = { method = strategy.name, success = ok, source = src }
    if ok then
      if debug then
        notify.debug("DebugViews: ✓ captured via " .. src)
      end
      return true, msgs, src
    end
  end

  -- Every strategy came back empty rather than throwing: the message
  -- history is genuinely empty, not broken -- report as a (empty) success
  -- so the caller's "no messages to capture" branch handles it.
  if not any_errored then
    return true, "", "no messages recorded yet"
  end

  local details = {}
  for _, attempt in ipairs(attempts) do
    details[#details + 1] = string.format("  • %s: %s", attempt.method, attempt.source)
  end

  return false, nil, "all methods failed:\n" .. table.concat(details, "\n")
end

---Capture :messages with optional file save and clipboard.
---
--- Reports only status, never notifies the user — the two call sites
--- (`debugging.views.messages_capture` and the `<lt>c` keymap in
--- `debugging.bindings.keymaps`) decide whether/how to surface the result.
--- `debug=true` diagnostics are the one exception: they are an explicit,
--- opt-in instrumentation request from the caller, not user-facing error
--- reporting, so they still notify directly.
---@param opts Dbg.Views.CaptureOpts|nil
---@return boolean success
---@return string|nil content
---@return string detail  Human-readable summary (success) or failure reason
function M.capture_messages(opts)
  opts = opts or {}
  local debug = opts.debug == true
  local save_file = opts.save_file ~= false
  local clipboard = opts.clipboard ~= false

  local dir, logfile = resolve_paths()
  if debug then
    notify.debug(("DebugViews: dir=%s\nlog=%s"):format(dir, logfile))
  end

  local ok_capture, messages, source = capture_messages_raw(debug)
  if not ok_capture or not messages then
    return false,
      nil,
      "Failed to capture messages.\n"
        .. (source or "unknown error")
        .. "\n\n"
        .. "Suggestions:\n"
        .. " 1. Try :Noice all to view messages\n"
        .. " 2. Try :messages to check if messages exist\n"
        .. " 3. Enable debug mode: :lua require('debugging.views.capture').capture_messages({debug=true})"
  end

  messages = rstrip(messages)
  local line_count = require("lib.lua.strings.core").count_lines(messages)

  if debug then
    notify.debug(
      ("DebugViews: captured %d bytes, %d lines via %s"):format(#messages, line_count, source)
    )
  end

  if messages == "" then
    return false, "", "no messages to capture (empty content)"
  end

  local success_operations = {}
  local errors = {}

  if save_file then
    local ok_write, err = write_file(logfile, messages)
    if not ok_write then
      errors[#errors + 1] = "write failed: " .. tostring(err)
    else
      table.insert(
        success_operations,
        string.format("%d lines → %s", line_count, vim.fn.fnamemodify(logfile, ":t"))
      )
    end
  end

  if clipboard then
    local ok_clip = copy_to_clipboard(messages, debug)
    if not ok_clip then
      errors[#errors + 1] = "clipboard not available. Install: pbcopy/wl-copy/xclip/xsel/clip.exe"
    else
      table.insert(success_operations, string.format("%d lines → clipboard", line_count))
    end
  end

  local detail_parts = {}
  if #success_operations > 0 then
    detail_parts[#detail_parts + 1] = "✓ " .. table.concat(success_operations, " | ")
  end
  for _, err in ipairs(errors) do
    detail_parts[#detail_parts + 1] = "✗ " .. err
  end
  if debug and source then
    detail_parts[#detail_parts + 1] = "(via " .. source .. ")"
  end

  return #success_operations > 0, messages, table.concat(detail_parts, "\n")
end

return M
