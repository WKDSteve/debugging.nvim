-- `:Debug proc start 60000` wraps `vim.fn.system`, `vim.system` and `jobstart` (lib.nvim.system.proc_trace); a command
-- that starts a process afterwards lands in the log with its duration (a traceback and a SLOW warning only over the
-- threshold, so none interrupts the sheet).
-- `:Debug proc stop` puts the originals back, `:Debug proc log` opens the log in a tab.
--
-- The traced start here is the one of `:Debug performance startup` (a headless Neovim), as a user would trace a slow
-- command of the editor.
return {
  id = "debugging.proc-trace",
  task = "debugging.nvim/abnahme-zwischenablage-startup-benchmark-und-proc-watch-von",
  feature = "debugging.proc-trace",
  title = "debugging.nvim: :Debug proc start/stop/log records a command's process start and opens the log",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I")
      vim.o.swapfile = false
      require("debugging").setup({})]],
      note = "the real setup with its defaults",
    },
    { keys = ":Debug proc start 60000<CR>", note = "trace every start, warn about none" },
    {
      expect = [[vim.fn.execute("messages"):find("tracing active", 1, true) ~= nil]],
      note = "the user is told where the log goes",
    },
    { keys = ":Debug performance startup<CR>", note = "a command that starts a process" },
    {
      wait = [[vim.bo.filetype == "startup-benchmark"]],
      timeout = 30000,
      note = "its report is there, so its start is over",
    },
    { keys = ":Debug proc stop<CR>", note = "stop tracing" },
    {
      expect = [[not require("lib.nvim.system.proc_trace").is_active()]],
      note = "tracing is off again",
    },
    { keys = ":Debug proc log<CR>", note = "open the log" },
    {
      wait = [[vim.fn.expand("%:t") == "proc_trace.log"]],
      note = "the log is the current buffer, in a tab of its own",
    },
    {
      expect = [[#vim.api.nvim_list_tabpages() == 2]],
      note = "a new tab",
    },
    {
      expect = [[table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("vim.system", 1, true) ~= nil]],
      note = "the start of the headless Neovim is logged",
    },
    {
      expect = [[table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("--startuptime", 1, true) ~= nil]],
      note = "with its command line",
    },
  },
  judge = {},
  manual = {},
}
