-- `:Debug proc watch 2` opens a terminal split running the bundled watcher
-- (`scripts/watch-nvim-procs.ps1`, pwsh or Windows PowerShell, a read-only CIM query of the editor's process tree)
-- for two seconds; it ends with a summary table. The watcher is Windows only: on Linux and macOS the command says
-- which tools to use instead and opens nothing, so every check below holds on both.
return {
  id = "debugging.proc-watch",
  feature = "debugging.proc-watch",
  title = "debugging.nvim: :Debug proc watch 2 runs the process watcher in a terminal split (a hint off Windows)",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I")
      vim.o.swapfile = false
      _G.win32 = vim.fn.has("win32") == 1
      require("debugging").setup({})]],
      note = "the real setup with its defaults",
    },
    { keys = ":Debug proc watch 2<CR>", note = "watch for two seconds" },
    {
      wait = [[not _G.win32 or vim.bo.buftype == "terminal"]],
      timeout = 5000,
      note = "Windows: a terminal buffer is current",
    },
    {
      expect = [[not _G.win32 or #vim.api.nvim_list_wins() == 2]],
      note = "Windows: in a split",
    },
    {
      wait = [[not _G.win32 or vim.fn.jobwait({ vim.bo.channel }, 0)[1] ~= -1]],
      timeout = 30000,
      note = "Windows: the watcher ends after its two seconds",
    },
    {
      expect = [[not _G.win32 or table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("ZUSAMMENFASSUNG", 1, true) ~= nil]],
      note = "Windows: it printed its summary",
    },
    {
      expect = [[_G.win32 or vim.fn.execute("messages"):find("Windows-only", 1, true) ~= nil]],
      note = "elsewhere: the user is told it is Windows only",
    },
    {
      expect = [[_G.win32 or #vim.api.nvim_list_wins() == 1]],
      note = "elsewhere: nothing was opened",
    },
    { input = "<C-\\><C-n>", note = "back to normal mode" },
  },
  judge = {},
  manual = {
    "Once on Windows while a freeze happens: :Debug proc watch lists the child process that lived longest at the top",
  },
}
