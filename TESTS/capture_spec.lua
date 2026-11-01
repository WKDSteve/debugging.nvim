-- TESTS/capture_spec.lua
-- Covers `debugging.views.capture`: the Noice-message extraction recursion
-- (`extract_noice_text`, exercised indirectly through every Noice retrieval
-- strategy) and the real `:messages`/`nvim_exec2` fallbacks, the empty-
-- content guard, and the save_file/clipboard sink bookkeeping.
--
-- Noice itself is not a dependency of this suite, so its module and every
-- shape it can hand back are faked via `package.loaded`. The plain
-- `vim.fn.execute('messages')` / `nvim_exec2('messages')` fallbacks are
-- exercised for real, against real `:messages` history this spec adds via
-- `echomsg`.

return function(H)
  local capture = require("debugging.views.capture")
  local orig_base_dir = capture.base_dir
  -- the default is debug state, not a folder of the config repository (and the health check looks at the same one)
  H.eq(
    orig_base_dir,
    vim.fn.stdpath("state") .. "/debug_views",
    "capture: the default directory is below stdpath('state')"
  )
  local orig_noice = package.loaded["noice"]
  local orig_manager = package.loaded["noice.message.manager"]

  local function clear_noice_stubs()
    package.loaded["noice"] = nil
    package.loaded["noice.message.manager"] = nil
  end

  local ok, err = pcall(function()
    -- ============================================================ Method 1: manager

    clear_noice_stubs()
    package.loaded["noice"] = {}
    local manager_get_opts
    package.loaded["noice.message.manager"] = {
      get = function(_, opts)
        manager_get_opts = opts -- asserted on below, outside capture's own pcall boundary
        return {
          { _lines = { { "part1", "part2" } } }, -- table-of-parts line
          {
            content = function()
              return "computed text"
            end,
          },
          { message = "direct message field" },
        }
      end,
    }

    local ok1, content1, detail1 =
      capture.capture_messages({ debug = true, clipboard = false, save_file = false })
    H.eq(manager_get_opts.history, true, "capture: manager.get is asked for full history")
    H.ok(not ok1, "capture: neither sink requested -> reported as not-successful (see README note)")
    H.match(content1 or "", "part1part2", "capture: manager _lines-of-parts extraction")
    H.match(content1 or "", "computed text", "capture: manager content%-function extraction")
    H.match(content1 or "", "direct message field", "capture: manager .message string extraction")
    H.match(
      detail1,
      "noice%.manager %(3 messages%)",
      "capture: debug detail names the manager source"
    )

    -- All-whitespace content collapses to "" after rstrip -- the dedicated
    -- empty-content guard, not a generic capture failure.
    package.loaded["noice.message.manager"] = {
      get = function()
        return { "   " }
      end,
    }
    local ok2, content2, detail2 =
      capture.capture_messages({ save_file = false, clipboard = false })
    H.eq(ok2, false, "capture: whitespace-only content is not successful")
    H.eq(content2, "", "capture: whitespace-only content collapses to an empty string")
    H.match(detail2, "empty content", "capture: the empty-content guard explains why")

    -- ============================================================ Method 2: history

    clear_noice_stubs()
    package.loaded["noice"] = {
      history = {
        get = function()
          return { "hist line one", "hist line two" }
        end,
      },
    }
    local ok3, content3, detail3 =
      capture.capture_messages({ debug = true, save_file = false, clipboard = false })
    H.match(content3 or "", "hist line one", "capture: history extraction (line 1)")
    H.match(content3 or "", "hist line two", "capture: history extraction (line 2)")
    H.match(
      detail3,
      "noice%.history %(2 entries%)",
      "capture: debug detail names the history source"
    )
    H.ok(ok3 == false, "capture: history path still hits the neither-sink-requested branch")

    -- ============================================================= Method 3: buffer

    clear_noice_stubs()
    package.loaded["noice"] = {}
    local noice_buf = H.scratch("noice://message/all")
    vim.api.nvim_buf_set_lines(noice_buf, 0, -1, false, { "buffer line A", "", "buffer line B" })

    local _, content4, detail4 =
      capture.capture_messages({ debug = true, save_file = false, clipboard = false })
    H.match(content4 or "", "buffer line A", "capture: noice-buffer extraction (line A)")
    H.match(content4 or "", "buffer line B", "capture: noice-buffer extraction (line B)")
    H.match(detail4, "noice buffer", "capture: debug detail names the buffer source")
    vim.cmd("bwipeout! " .. noice_buf)

    -- ============================================================ Method 4: api.status

    clear_noice_stubs()
    package.loaded["noice"] = {
      api = {
        status = {
          message = {
            get = function()
              return "status bar message"
            end,
          },
        },
      },
    }
    local _, content5, detail5 =
      capture.capture_messages({ debug = true, save_file = false, clipboard = false })
    H.eq(content5, "status bar message", "capture: api.status fallback extraction")
    H.match(detail5, "noice%.api%.status", "capture: debug detail names the api.status source")

    -- ==================================================== fallback: real :messages

    clear_noice_stubs() -- noice absent entirely -> falls through to execute/exec2

    vim.cmd("echomsg 'debugging_capture_spec_marker'")
    local ok6, content6, detail6 =
      capture.capture_messages({ save_file = false, clipboard = false })
    H.eq(
      ok6,
      false,
      "capture: real :messages, both sinks off -> still the neither-requested branch"
    )
    H.match(
      content6 or "",
      "debugging_capture_spec_marker",
      "capture: real :messages content is captured"
    )
    H.eq(detail6, "", "capture: neither-sink-requested detail is empty with debug=false")

    -- ===================================================== ERR-11: empty vs errored
    --
    -- try_execute()/try_exec2() used to report "returned empty" both when the
    -- underlying call legitimately found nothing AND when it threw, so a
    -- clean, empty `:messages` history looked identical to a broken capture
    -- pipeline. `:messages` in this shared test session already has content
    -- from earlier specs' notifications, so the real functions are stubbed
    -- here instead of relying on the ambient history being empty.

    clear_noice_stubs() -- noice absent -> falls through to execute/exec2 either way

    local orig_execute, orig_exec2 = vim.fn.execute, vim.api.nvim_exec2

    -- Case 1: both fallbacks legitimately produce nothing (no error) -> the
    -- dedicated "no messages to capture" branch, not a reported failure.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.execute = function()
      return ""
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_exec2 = function()
      return { output = "" }
    end
    local ok_empty, content_empty, detail_empty =
      capture.capture_messages({ save_file = false, clipboard = false })
    H.eq(ok_empty, false, "capture: legitimately empty messages is not 'successful'")
    H.eq(content_empty, "", "capture: legitimately empty messages yields an empty string")
    H.match(
      detail_empty,
      "no messages to capture %(empty content%)",
      "capture: legitimately empty messages is reported as empty, not as a failure"
    )

    -- Case 2: both fallbacks throw -> a real failure, reported distinctly
    -- from case 1 rather than with the same "returned empty" text.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.execute = function()
      error("boom (execute)")
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_exec2 = function()
      error("boom (exec2)")
    end
    local ok_err, content_err, detail_err =
      capture.capture_messages({ save_file = false, clipboard = false })
    H.eq(ok_err, false, "capture: a genuine failure is not 'successful'")
    H.eq(content_err, nil, "capture: a genuine failure has no content")
    H.match(
      detail_err,
      "Failed to capture messages",
      "capture: a genuine failure is reported as a failure, not as empty content"
    )
    H.ok(
      not detail_err:match("empty content"),
      "capture: a genuine failure's detail is distinguishable from the empty%-content case"
    )

    vim.fn.execute, vim.api.nvim_exec2 = orig_execute, orig_exec2

    -- ============================================================= save_file / clipboard
    --
    -- Whether the clipboard sink can succeed at all depends on the
    -- machine: `lib.nvim.cross.copy_to_clipboard` needs either a real
    -- clipboard provider or one of pbcopy/wl-copy/xclip/xsel/clip.exe on
    -- PATH, none of which a bare CI runner has. That used to be invisible
    -- -- the function reported success regardless, from trusting
    -- `pcall(setreg, ...)` not raising as proof the value stuck -- but
    -- lib.nvim fixed that at the source (verifies the register round
    -- trip), so this suite has to know which outcome it is looking at
    -- instead of assuming the happy path.
    --
    -- `save_file` is unconditional either way: it needs nothing from the
    -- environment, so its assertions run regardless of what the probe
    -- below finds.

    local tmp_dir = vim.fs.normalize(vim.fn.tempname())
    capture.base_dir = tmp_dir

    -- Probed with its own marker, not the one the real assertions use
    -- below: if this call succeeds, `+` already carries proof of it and
    -- there is no need to write and immediately overwrite the register a
    -- second time before the real capture runs.
    vim.fn.setreg("+", "")
    local clipboard_works = require("lib.nvim.cross.copy_to_clipboard")("debugging_capture_probe")
    vim.fn.setreg("+", "")

    vim.cmd("echomsg 'debugging_capture_spec_marker_2'")
    local ok7, content7, detail7 = capture.capture_messages({ save_file = true, clipboard = true })
    H.ok(ok7, "capture: with save_file always available, capture reports success")
    H.match(
      content7 or "",
      "debugging_capture_spec_marker_2",
      "capture: save_file/clipboard content matches"
    )
    H.match(detail7, "%.log", "capture: detail reports the written logfile's basename")

    -- `glob` reads its argument as a pattern, not a path: under Windows,
    -- $TEMP is the 8.3 short form for any profile name over eight
    -- characters, and glob then tries (and fails) to resolve the `~1` in it
    -- as a home-directory reference, silently returning an empty list.
    local globbable = require("lib.nvim.fs.globbable")
    local written = vim.fn.glob(globbable(tmp_dir) .. "/messages-*.log", false, true)
    H.eq(#written, 1, "capture: save_file wrote exactly one timestamped logfile")
    local file_content = table.concat(vim.fn.readfile(written[1]), "\n")
    H.match(
      file_content,
      "debugging_capture_spec_marker_2",
      "capture: the logfile holds the captured content"
    )

    if clipboard_works then
      H.match(detail7, "→ clipboard", "capture: detail reports the clipboard sink")
      H.match(
        vim.fn.getreg("+"),
        "debugging_capture_spec_marker_2",
        "capture: the clipboard sink was written"
      )
    else
      -- No provider and no external tool on this machine -- the honest
      -- outcome, and the one every CI runner actually hits. capture_messages
      -- degrades a single failed sink rather than failing the whole call
      -- (save_file still succeeded above), which is the behaviour under
      -- test here.
      H.match(
        detail7,
        "clipboard not available",
        "capture: a failed clipboard sink is reported, not silently dropped"
      )
      H.eq(
        vim.fn.getreg("+"),
        "",
        "capture: the register is untouched when the sink honestly failed"
      )
    end

    vim.fn.delete(tmp_dir, "rf")
  end)

  capture.base_dir = orig_base_dir
  clear_noice_stubs()
  package.loaded["noice"] = orig_noice
  package.loaded["noice.message.manager"] = orig_manager
  if not ok then
    error(err, 0)
  end
end
