-- The capture key (`<c`, the default prefix `<lt>` and `c`) writes `:messages` to a log file below
-- `stdpath("state")` and to the system clipboard. The clipboard goes through lib.nvim.cross.copy_to_clipboard: the `+`
-- register first, an OS tool when that does not take the text. The sheet's `+` register has a provider that keeps
-- nothing (as on a machine without one), so the OS tool is started: `powershell ... Set-Clipboard` (Windows), `pbcopy`
-- (macOS), `wl-copy`/`xclip`/`xsel` (Linux), `clip.exe` (WSL). They are recording stand-ins: the real clipboard of
-- the machine is never touched.
return {
  id = "debugging.messages-capture",
  feature = "debugging.messages-capture",
  title = "debugging.nvim: <c writes :messages to a log file and hands it to the system clipboard tool",
  engine = "rpc",
  sizes = { { rows = 20, cols = 120 } },
  fakes = { "powershell", "pbcopy", "wl-copy", "xclip", "xsel", "clip.exe" },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I")
      vim.o.swapfile = false
      _G.programs = { "powershell", "pbcopy", "wl-copy", "xclip", "xsel", "clip.exe" }
      if vim.fn.has("win32") == 1 then
        local path = vim.fn.getcwd() .. "/TESTS/sheets/fixtures/windows_stand_in_argv.lua"
        assert(load(table.concat(vim.fn.readfile(path), "\n"), "=windows stand-in argv"))(_G.programs)
      end
      local function keep_nothing() end
      vim.g.clipboard = {
        name = "sheet-none",
        copy = { ["+"] = keep_nothing, ["*"] = keep_nothing },
        paste = { ["+"] = function() return {} end, ["*"] = function() return {} end },
      }
      _G.calls = function()
        local fp, out = require("testing.fake_programs"), {}
        for _, p in ipairs(_G.programs) do
          for _, call in ipairs(fp.read(vim.env.TESTING_FAKES, p)) do
            out[#out + 1] = { program = p, argv = call.argv }
          end
        end
        return out
      end
      require("debugging").setup({})]],
      note = "the real setup with its keys; the + register keeps nothing, the clipboard tools are stand-ins",
    },
    {
      lua = [[vim.cmd('echomsg "build finished: 3 warnings"')]],
      note = "a message to capture",
    },
    { keys = "<c", note = "the capture key" },
    { wait = "#_G.calls() == 1", timeout = 5000, note = "one clipboard tool was started" },
    {
      expect = [[vim.fn.execute("messages"):find("lines → clipboard", 1, true) ~= nil]],
      note = "the user is told the lines went to the clipboard",
    },
    {
      expect = [[vim.fn.execute("messages"):find("→ messages%-[%d%-]+%.log") ~= nil]],
      note = "and to a log file",
    },
    {
      expect = [[#vim.fn.glob(vim.fn.stdpath("state") .. "/debug_views/messages-*.log", true, true) == 1]],
      note = "the log file exists",
    },
  },
  judge = {},
  manual = {
    "Once in the real editor: <c, then paste in another program shows the messages",
  },
}
