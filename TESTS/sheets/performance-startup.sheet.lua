-- `:Debug performance startup 2` starts a fresh headless Neovim under `--startuptime` twice, one after the other
-- (`vim.system` with a callback, the editor stays usable), and opens the report in a scratch split. The child
-- editor's config is the sheet's sandbox (`XDG_CONFIG_HOME`), so the measured Neovim starts without a user config.
return {
  id = "debugging.performance-startup",
  feature = "debugging.performance-startup",
  title = "debugging.nvim: :Debug performance startup 2 measures two headless starts and shows the report",
  engine = "rpc",
  sizes = { { rows = 30, cols = 110 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I")
      vim.o.swapfile = false
      require("debugging").setup({})]],
      note = "the real setup with its defaults",
    },
    { keys = ":Debug performance startup 2<CR>", note = "two runs" },
    {
      wait = [[vim.bo.filetype == "startup-benchmark"]],
      timeout = 60000,
      note = "the report split is current",
    },
    {
      expect = [[vim.api.nvim_buf_get_lines(0, 3, 4, false)[1] == "Runs: 2"]],
      note = "both runs are counted",
    },
    {
      expect = [[(tonumber(vim.api.nvim_buf_get_lines(0, 4, 5, false)[1]:match("avg ([%d%.]+) ms")) or 0) > 0]],
      note = "the average total is a positive number of milliseconds",
    },
    {
      expect = [[#vim.api.nvim_list_wins() == 2]],
      note = "in a split next to the file",
    },
  },
  judge = {},
  manual = {
    "Once with the real config: :Debug performance startup 5 lists the slowest plugins of the config at the top",
  },
}
