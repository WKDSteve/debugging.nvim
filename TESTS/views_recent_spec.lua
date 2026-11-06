-- TESTS/views_recent_spec.lua
-- Covers `debugging.views.recent`: filter -> lib.nvim.messages.snapshot()
-- levels mapping, the ui.kit.message_log path (stubbed -- ui.nvim is not on
-- this suite's rtp) vs. the lib.nvim.output.viewer fallback, window-tag
-- reuse (focus instead of reopening), the live on_message subscription
-- respecting the filter, and unsubscribe-on-close.

return function(H)
  local eq, ok = H.eq, H.ok
  local orig_notify = vim.notify

  local run_ok, err = pcall(function()
    package.loaded["debugging.views.recent"] = nil

    -- A fake lib.nvim.messages: records every snapshot() call's opts,
    -- exposes a single on_message listener for the test to drive directly
    -- (push isn't needed -- the real module's push/ring/kind logic has its
    -- own suite in lib.nvim).
    local snapshot_calls = {}
    local listener
    local orig_messages = package.loaded["lib.nvim.messages"]
    package.loaded["lib.nvim.messages"] = {
      snapshot = function(opts)
        snapshot_calls[#snapshot_calls + 1] = opts
        return opts.entries_to_return or {}
      end,
      on_message = function(fn)
        listener = fn
        return fn
      end,
      off_message = function(fn)
        if listener == fn then
          listener = nil
        end
      end,
    }

    local orig_views = package.loaded["debugging.views"]
    package.loaded["debugging.views"] = {
      get_recent_config = function()
        return {
          window_s = 10,
          min_entries = 0, -- strictly window_s here; the top-up has its own block below
          order = "newest_last",
          collapsed_default = false,
        }
      end,
    }

    -- ============================================================= fallback
    -- ui.kit genuinely is not installed in this test env -- require("ui.kit")
    -- fails for real, exercising the actual fallback branch, not a stub of it.
    do
      snapshot_calls = {}
      local seen = {}
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function(msg, level)
        seen[#seen + 1] = { msg = tostring(msg), level = level }
      end

      local orig_viewer = package.loaded["lib.nvim.output.viewer"]
      local dumped
      local fallback_bufnr = vim.api.nvim_create_buf(false, true)
      local fallback_winid = vim.api.nvim_open_win(fallback_bufnr, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 10,
        height = 3,
      })
      package.loaded["lib.nvim.output.viewer"] = {
        show_lines = function(title, lines, opts)
          dumped = { title = title, lines = lines, opts = opts }
          return { winid = fallback_winid, bufnr = fallback_bufnr }
        end,
      }

      local recent = require("debugging.views.recent")
      recent.show("error")

      eq(snapshot_calls[1].levels[1], vim.log.levels.ERROR, "error filter: only ERROR level")
      ok(dumped ~= nil, "no ui.kit: falls back to lib.nvim.output.viewer.show_lines")
      eq(dumped.lines[1], "(no messages)", "fallback: empty snapshot shows the placeholder line")
      ok(#seen > 0, "fallback: notifies that live updates/pagination are unavailable")

      -- A 1-line snapshot ("(no messages)" or a single entry) must still ask
      -- for at least a 2-row window -- lib.nvim.window.tag.find() requires
      -- height > 1 strictly, so a literal height=1 window would be tagged
      -- but never findable, silently defeating the tagging above.
      ok(dumped.opts ~= nil, "show_lines was called with an opts table")
      ok(dumped.opts.height >= 2, "height is floored at 2 even for a 1-line snapshot")

      -- The fallback window must be tagged too -- otherwise display.clear_all()
      -- (the `<x>` cleanup) and M.show()'s own reuse check silently don't see
      -- it, since both only ever look through lib.nvim.window.tag.
      local window_tag = require("lib.nvim.window").tag
      eq(
        window_tag.get(fallback_winid),
        "recent_errors",
        "the fallback popup's window is tagged too"
      )

      pcall(vim.api.nvim_win_close, fallback_winid, true)
      package.loaded["lib.nvim.output.viewer"] = orig_viewer
    end

    -- ===================================================== fallback multiline
    -- Multi-line contents (Lua errors, stack traces) must be split before they
    -- reach the viewer, which rejects embedded newlines; the height follows the
    -- split line count, not the entry count.
    do
      local orig_viewer = package.loaded["lib.nvim.output.viewer"]
      local dumped
      package.loaded["lib.nvim.output.viewer"] = {
        show_lines = function(_, lines, opts)
          dumped = { lines = lines, opts = opts }
        end,
      }
      local now_ms = vim.uv.hrtime() / 1e6
      local entries = {
        { content = "a\nb", level = 2, time_ms = now_ms },
        { content = "c\r\nd\r\ne", level = 2, time_ms = now_ms },
        { content = "f\n", level = 2, time_ms = now_ms },
        { content = "p\rq", level = 2, time_ms = now_ms },
      }
      local fake_messages = package.loaded["lib.nvim.messages"]
      local orig_snapshot = fake_messages.snapshot
      fake_messages.snapshot = function()
        return entries
      end
      require("debugging.views.recent").show("all")
      ok(dumped ~= nil, "multiline: show_lines is reached without error")
      eq(
        #dumped.lines,
        7,
        "multiline: 2 + 3 + 1 + 1 lines (CRLF split, trailing LF dropped, lone CR removed)"
      )
      for _, line in ipairs(dumped.lines) do
        ok(not line:find("[\r\n]"), "multiline: no line holds a newline")
      end
      ok(dumped.lines[1]:find("^%[%ds ago%] a$") ~= nil, "multiline: age prefix on the first line")
      ok(dumped.lines[2]:find("^%s+b$") ~= nil, "multiline: continuation line is indented")
      eq(dumped.opts.height, 7, "multiline: height follows the split line count")
      fake_messages.snapshot = orig_snapshot
      package.loaded["lib.nvim.output.viewer"] = orig_viewer
    end

    -- ============================================================ non_error
    do
      snapshot_calls = {}
      local recent = require("debugging.views.recent")

      local orig_viewer = package.loaded["lib.nvim.output.viewer"]
      package.loaded["lib.nvim.output.viewer"] = { show_lines = function() end }
      recent.show("non_error")
      local levels = snapshot_calls[1].levels
      local has_error = false
      for _, l in ipairs(levels) do
        if l == vim.log.levels.ERROR then
          has_error = true
        end
      end
      eq(has_error, false, "non_error filter: ERROR is excluded")
      eq(#levels, 4, "non_error filter: the other four levels are included")
      package.loaded["lib.nvim.output.viewer"] = orig_viewer
    end

    -- ================================================================== all
    do
      snapshot_calls = {}
      local orig_viewer = package.loaded["lib.nvim.output.viewer"]
      package.loaded["lib.nvim.output.viewer"] = { show_lines = function() end }
      require("debugging.views.recent").show("all")
      eq(snapshot_calls[1].levels, nil, "all filter: no levels restriction")
      package.loaded["lib.nvim.output.viewer"] = orig_viewer
    end

    -- ======================================================= unknown filter
    do
      local seen = {}
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function(msg, level)
        seen[#seen + 1] = { msg = tostring(msg), level = level }
      end
      ok(pcall(require("debugging.views.recent").show, "bogus"), "an unknown filter does not raise")
      ok(#seen > 0, "an unknown filter is reported via notify.warn")
    end

    -- ============================================== window-tag reuse (real window)
    do
      local window_tag = require("lib.nvim.window").tag
      vim.cmd("vsplit")
      local win = vim.api.nvim_get_current_win()
      window_tag.set(win, "recent_messages")

      local open_calls = 0
      package.loaded["ui.kit"] = {
        message_log = function()
          open_calls = open_calls + 1
          return nil
        end,
      }

      require("debugging.views.recent").show("non_error")
      eq(open_calls, 0, "an already-open tagged window is focused, not reopened")
      eq(vim.api.nvim_get_current_win(), win, "focus actually moved to the existing window")

      vim.cmd("only")
      package.loaded["ui.kit"] = nil
    end

    -- ===================================== ui.kit.message_log path (stubbed)
    do
      vim.cmd("only")
      local fake_bufnr = vim.api.nvim_create_buf(false, true)
      local fake_winid = vim.api.nvim_open_win(fake_bufnr, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 10,
        height = 3,
      })

      local open_opts
      local appended = {}
      local close_cb
      local fake_handle = {
        surf = { winid = fake_winid, bufnr = fake_bufnr },
        append = function(_, entries)
          for _, e in ipairs(entries) do
            appended[#appended + 1] = e
          end
        end,
        on_close = function(_, cb)
          close_cb = cb
        end,
      }
      package.loaded["ui.kit"] = {
        message_log = function(opts)
          open_opts = opts
          return fake_handle
        end,
      }

      snapshot_calls = {}
      require("debugging.views.recent").show("error")

      ok(open_opts ~= nil, "ui.kit.message_log.open is called when ui.kit is present")
      eq(open_opts.title, "Recent errors", "error filter: title mentions errors")
      ok(type(open_opts.load_more) == "function", "load_more callback is wired")

      -- The window-tag primitive is reused here too, not reimplemented --
      -- same lib.nvim.window.tag the display.lua path already relies on.
      local window_tag = require("lib.nvim.window").tag
      eq(window_tag.get(fake_winid), "recent_errors", "the new popup's window is tagged")

      -- Live feed: the on_message listener only appends entries matching
      -- this view's filter.
      ok(listener ~= nil, "recent.show subscribed to lib.nvim.messages.on_message")
      listener({ level = vim.log.levels.ERROR, content = "boom" })
      eq(#appended, 1, "a matching live entry is appended")
      listener({ level = vim.log.levels.INFO, content = "ignored" })
      eq(#appended, 1, "a non-matching live entry is NOT appended")

      -- load_more("older") extends the window and does not touch "newer".
      local before = #snapshot_calls
      open_opts.load_more("newer")
      eq(#snapshot_calls, before, "load_more('newer') does not query the store")
      open_opts.load_more("older")
      -- The ring is empty here, so the has-older probe is the only query: it must ask for
      -- entries BEFORE what is loaded, with this view's level filter (a call count alone
      -- would be satisfied by any query at all).
      eq(#snapshot_calls, before + 1, "load_more('older') queries once for an earlier window")
      local probe = snapshot_calls[#snapshot_calls]
      ok(probe.until_ms ~= nil, "the probe is bounded above by what is loaded")
      ok(probe.since_ms == nil, "and open below: everything older")
      eq(probe.levels[1], vim.log.levels.ERROR, "with the view's own level filter")

      -- on_close unsubscribes.
      ok(close_cb ~= nil, "on_close callback was registered")
      close_cb()
      ok(listener == nil, "closing the popup unsubscribes from lib.nvim.messages")

      pcall(vim.api.nvim_win_close, fake_winid, true)
      package.loaded["ui.kit"] = nil
    end

    -- ============================== paging across a quiet stretch (stubbed kit)
    -- A gap longer than window_s between two messages used to make the first
    -- load_more("older") come back empty, which the popup reads as "nothing
    -- left" -- the older history stayed out of reach for good.
    do
      vim.cmd("only")
      local fake_bufnr = vim.api.nvim_create_buf(false, true)
      local fake_winid = vim.api.nvim_open_win(fake_bufnr, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 10,
        height = 3,
      })
      local now_ms = vim.uv.hrtime() / 1e6
      -- seconds ago -> a ring entry; 3 recent, then a 50 s gap, then 3 old, then 1 ancient
      local ring = {}
      for _, ago in ipairs({ 300, 62, 61, 60, 4, 3, 2 }) do
        ring[#ring + 1] = {
          time_ms = now_ms - ago * 1000,
          level = vim.log.levels.INFO,
          content = tostring(ago),
        }
      end
      local paging_messages = package.loaded["lib.nvim.messages"]
      local orig_snapshot = paging_messages.snapshot
      paging_messages.snapshot = function(opts)
        local out = {}
        for _, e in ipairs(ring) do
          if
            (not opts.since_ms or e.time_ms >= opts.since_ms)
            and (not opts.until_ms or e.time_ms <= opts.until_ms)
          then
            out[#out + 1] = e
          end
        end
        return out
      end

      local open_opts
      package.loaded["ui.kit"] = {
        message_log = function(opts)
          open_opts = opts
          return {
            surf = { winid = fake_winid, bufnr = fake_bufnr },
            append = function() end,
            on_close = function() end,
          }
        end,
      }
      require("debugging.views.recent").show("all")

      eq(#open_opts.entries, 3, "the popup opens with the last window_s only")
      eq(open_opts.has_more_older, true, "older entries exist: the hint is offered")

      local contents = {}
      local pages = 0
      while true do
        local page = open_opts.load_more("older")
        if #page == 0 then
          break
        end
        pages = pages + 1
        for i = #page, 1, -1 do
          table.insert(contents, 1, page[i].content)
        end
        ok(pages < 10, "paging terminates")
      end
      eq(
        table.concat(contents, ","),
        "300,62,61,60",
        "every older entry was reachable, oldest first"
      )
      eq(pages, 2, "the 50 s gap cost no empty page: 60-62 s, then the ancient one")

      -- min_entries: a popup opened after a quiet minute still shows the newest few.
      package.loaded["debugging.views"].get_recent_config = function()
        return { window_s = 10, min_entries = 5, order = "newest_last", collapsed_default = false }
      end
      pcall(vim.api.nvim_win_close, fake_winid, true)
      fake_winid = vim.api.nvim_open_win(fake_bufnr, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 10,
        height = 3,
      })
      require("debugging.views.recent").show("all")
      local topped = {}
      for _, e in ipairs(open_opts.entries) do
        topped[#topped + 1] = e.content
      end
      eq(
        table.concat(topped, ","),
        "61,60,4,3,2",
        "the 5 newest, although only 3 are within window_s"
      )
      local page = open_opts.load_more("older")
      local first = {}
      for _, e in ipairs(page) do
        first[#first + 1] = e.content
      end
      eq(
        table.concat(first, ","),
        "62",
        "paging continues exactly before the topped-up entries, no duplicates"
      )
      local second = {}
      for _, e in ipairs(open_opts.load_more("older")) do
        second[#second + 1] = e.content
      end
      eq(table.concat(second, ","), "300", "the ancient entry follows, once")
      eq(#open_opts.load_more("older"), 0, "then the ring is exhausted")
      eq(#open_opts.entries, 5, "the entries handed over are not mutated by paging")

      -- `-`: a page taken out again comes back with the next `+`, none is skipped.
      local function page_text()
        local out = {}
        for _, e in ipairs(open_opts.load_more("older")) do
          out[#out + 1] = e.content
        end
        return table.concat(out, ",")
      end
      open_opts.on_unload("older", 1)
      eq(page_text(), "300", "the page unloaded last loads again")
      open_opts.on_unload("older", 1)
      open_opts.on_unload("older", 1)
      eq(page_text(), "62", "unloading twice goes back two pages")
      eq(page_text(), "300", "and paging goes on from there")
      open_opts.on_unload("older", 1)
      open_opts.on_unload("older", 1)
      open_opts.on_unload("older", 1)
      eq(page_text(), "62", "unloading more than was loaded stays on the first page")

      -- An empty ring offers no "more above" hint at all.
      ring = {}
      require("debugging.views.recent").show("error")
      eq(#open_opts.entries, 0, "empty ring: nothing to show")
      eq(open_opts.has_more_older, false, "empty ring: no hint for history that does not exist")
      pcall(vim.api.nvim_win_close, fake_winid, true)
      paging_messages.snapshot = orig_snapshot
      package.loaded["ui.kit"] = nil
    end

    -- ============== messages stored while the popup is being built (stubbed kit)
    -- The subscription is made before the snapshot, so an entry stored while the float
    -- opens is neither lost nor shown twice.
    do
      vim.cmd("only")
      local bufnr = vim.api.nvim_create_buf(false, true)
      local winid = vim.api.nvim_open_win(bufnr, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 10,
        height = 3,
      })
      local fake_messages = package.loaded["lib.nvim.messages"]
      local orig_snapshot = fake_messages.snapshot
      local dup = { time_ms = 5, level = vim.log.levels.ERROR, content = "in the snapshot" }
      fake_messages.snapshot = function()
        return { vim.deepcopy(dup) }
      end
      local appended = {}
      package.loaded["ui.kit"] = {
        message_log = function()
          -- Stored while the window opens: one the snapshot already has, one new, one
          -- of another level that this view filters out.
          listener(dup)
          listener({ time_ms = 6, level = vim.log.levels.ERROR, content = "during build" })
          listener({ time_ms = 7, level = vim.log.levels.INFO, content = "wrong level" })
          return {
            surf = { winid = winid, bufnr = bufnr },
            append = function(_, list)
              for _, e in ipairs(list) do
                appended[#appended + 1] = e.raw.content
              end
            end,
            on_close = function() end,
          }
        end,
      }
      -- The error view: the tag of the non_error view is still on a real window from the
      -- window-tag-reuse block above.
      require("debugging.views.recent").show("error")
      eq(
        table.concat(appended, ","),
        "during build",
        "late entry shown once, duplicate and filtered one not"
      )
      listener({ time_ms = 8, level = vim.log.levels.ERROR, content = "live" })
      eq(appended[#appended], "live", "afterwards the feed is live")

      pcall(vim.api.nvim_win_close, winid, true)
      fake_messages.snapshot = orig_snapshot
      package.loaded["ui.kit"] = nil
    end

    -- ================================== entry header, tag and wrapped body
    -- A message wider than the float used to be one line the popup could neither show
    -- in full nor unfold. Each entry is now a header line (tag + title cut to fit) with
    -- the full text wrapped below it, which the kit folds with <CR>.
    do
      local recent = require("debugging.views.recent")
      local strw = vim.fn.strdisplaywidth

      eq(
        recent.entry_tag({
          level = vim.log.levels.ERROR,
          kind = "emsg",
          content = "E492: Not an editor command: foo",
        }),
        "ERROR E492 emsg",
        "tag: level, Vim error code and kind"
      )
      eq(
        recent.entry_tag({ level = vim.log.levels.INFO, kind = "notify", content = "plain" }),
        "",
        "tag: an INFO notify has nothing to say"
      )
      eq(
        recent.entry_tag({ level = vim.log.levels.WARN, source = "[my.mod]", content = "x" }),
        "WARN my.mod",
        "tag: the source, without brackets"
      )
      eq(
        recent.entry_tag({
          level = vim.log.levels.INFO,
          source = "[my.mod]",
          content = "[my.mod] x",
        }),
        "",
        "tag: a source the text already starts with is not repeated"
      )
      eq(
        recent.entry_tag({
          level = vim.log.levels.INFO,
          source = "gitsuite",
          content = "[gitsuite] pushed",
        }),
        "",
        "tag: a bare source the text starts with as [name] is not repeated (lib.nvim.notify)"
      )

      eq(
        recent.format_content({ level = vim.log.levels.INFO, content = "short" }, 80),
        "short",
        "a short one-line message stays one line"
      )

      local words = {}
      for i = 1, 60 do
        words[i] = "word" .. i
      end
      local long = table.concat(words, " ")
      local width = 60
      local shown = vim.split(
        recent.format_content({ level = vim.log.levels.ERROR, content = long }, width),
        "\n",
        { plain = true }
      )
      ok(#shown > 2, "a long one-line message gets a body to unfold")
      ok(shown[1]:find("^%[ERROR%] word1 ") ~= nil, "header: tag, then the title")
      ok(shown[1]:find("…$") ~= nil, "header: a cut title ends in an ellipsis")
      ok(strw(shown[1]) <= width, "header fits the width")
      local body = {}
      for i = 2, #shown do
        ok(strw(shown[i]) <= width, ("body row %d fits the width"):format(i))
        body[#body + 1] = vim.trim(shown[i])
      end
      eq(table.concat(body, " "), long, "the body is the full text, nothing lost")

      local multi = vim.split(
        recent.format_content(
          { level = vim.log.levels.INFO, content = "head\nline 2\r\nline 3\n" },
          60
        ),
        "\n",
        { plain = true }
      )
      eq(
        table.concat(multi, "|"),
        "head|line 2|line 3",
        "multi-line: a short title is not repeated"
      )

      local hard = recent.wrap_line(("x"):rep(25), 10)
      eq(#hard, 3, "a word longer than a row is cut hard")
      eq(hard[2], "  " .. ("x"):rep(8), "continuation rows are indented")
      local wide = recent.wrap_line(("äöü "):rep(10), 12)
      for _, row in ipairs(wide) do
        ok(strw(row) <= 12, "multibyte rows fit the width")
      end

      -- The folded row the kit draws ("[time] header  … (+N more lines)" plus fold mark and
      -- margin) must fit the window it can open (columns - 4), or it wraps onto a second
      -- screen line and the last entry drops out of view.
      local saved_columns = vim.o.columns
      local e492 = "E492: Not an editor command: " .. table.concat(words, " ")
      for _, columns in ipairs({ 80, 100 }) do
        vim.o.columns = columns
        for _, entry in ipairs({
          { level = vim.log.levels.ERROR, kind = "emsg", content = e492 },
          { level = vim.log.levels.ERROR, kind = "emsg", content = e492 .. "\nline 2\nline 3" },
          { level = vim.log.levels.INFO, content = "short head\n" .. e492 },
        }) do
          local rows = vim.split(recent.format_content(entry, columns - 12), "\n", { plain = true })
          local n = #rows - 1
          local folded = ("[%s] %s"):format("12:34:56 59m ago", rows[1])
            .. (n > 0 and ("  … (+%d more line%s)"):format(n, n == 1 and "" or "s") or "")
          ok(
            strw(folded) + 3 <= columns - 4,
            ("columns=%d: folded row of %d cells fits the window"):format(columns, strw(folded) + 3)
          )
        end
      end
      vim.o.columns = saved_columns

      -- A 64 KB single line (merged `:!cmd` output) must not freeze the popup.
      local huge = ("abcdefg "):rep(8192)
      local t0 = vim.uv.hrtime()
      local huge_rows = recent.wrap_line(huge, 88)
      local huge_ms = (vim.uv.hrtime() - t0) / 1e6
      ok(huge_ms < 300, ("wrapping 64 KB takes %.0f ms"):format(huge_ms))
      local huge_body = {}
      for i, row in ipairs(huge_rows) do
        if strw(row) > 88 then
          ok(false, ("64 KB row %d is %d cells"):format(i, strw(row)))
        end
        huge_body[i] = vim.trim(row)
      end
      eq(table.concat(huge_body, " "), vim.trim(huge), "64 KB: nothing lost")

      -- The popup entry follows its store entry: a `:!cmd` entry that grows in place
      -- shows the new text on the next redraw; time and level pass through.
      local raw = { time_ms = 42, level = vim.log.levels.INFO, content = "one" }
      local shown_entry = recent.display_entry(raw)
      eq(shown_entry.content, "one", "display entry: formatted content")
      eq(shown_entry.time_ms, 42, "display entry: time passes through")
      eq(shown_entry.raw, raw, "display entry: the store entry is reachable")
      raw.content = "one\ntwo"
      eq(shown_entry.content, "one\ntwo", "display entry: in-place growth is picked up")

      local now = vim.uv.hrtime() / 1e6
      local label = recent.format_time({ time_ms = now - 5000 }, now)
      ok(label:find("^%d%d:%d%d:%d%d 5s ago$") ~= nil, "time: wall clock plus age, got " .. label)

      -- Wired into the popup: entries formatted, wall-clock times, folded by default.
      vim.cmd("only")
      local bufnr = vim.api.nvim_create_buf(false, true)
      local winid = vim.api.nvim_open_win(bufnr, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 10,
        height = 3,
      })
      local fake_messages = package.loaded["lib.nvim.messages"]
      local orig_snapshot = fake_messages.snapshot
      fake_messages.snapshot = function(opts)
        return opts.until_ms and {}
          or { { time_ms = now, level = vim.log.levels.ERROR, content = long } }
      end
      local orig_cfg = package.loaded["debugging.views"].get_recent_config
      package.loaded["debugging.views"].get_recent_config = function()
        return { window_s = 10, min_entries = 0, wrap_width = 50 }
      end
      local open_opts
      package.loaded["ui.kit"] = {
        message_log = function(opts)
          open_opts = opts
          return {
            surf = { winid = winid, bufnr = bufnr },
            append = function() end,
            on_close = function() end,
          }
        end,
      }
      recent.show("all")
      eq(open_opts.collapsed_default, true, "folded by default")
      eq(open_opts.format_entry_time, recent.format_time, "wall-clock time labels")
      local rows = vim.split(open_opts.entries[1].content, "\n", { plain = true })
      ok(#rows > 2, "the long entry reaches the kit as a header plus a body")
      for _, row in ipairs(rows) do
        ok(strw(row) <= 50, "every row fits views.recent.wrap_width")
      end

      pcall(vim.api.nvim_win_close, winid, true)
      package.loaded["debugging.views"].get_recent_config = orig_cfg
      fake_messages.snapshot = orig_snapshot
      package.loaded["ui.kit"] = nil
    end

    package.loaded["lib.nvim.messages"] = orig_messages
    package.loaded["debugging.views"] = orig_views
    package.loaded["debugging.views.recent"] = nil
  end) -- pcall

  vim.notify = orig_notify
  if not run_ok then
    error(err, 0)
  end
end
