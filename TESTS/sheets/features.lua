-- TESTS/sheets/features.lua -- the functionalities of debugging.nvim that start a process (directly or through
-- lib.nvim), read by testing.nvim (`testing perf`, `testing sheets report`). A feature sheet names its entry with
-- `feature = "<id>"`; an entry without a sheet says why with `perf`.
--
-- The other :Debug categories (reports, autocmds, inspect, keylogger, markdown, filetree, neotest, module reload)
-- read the editor's own state and start no process; they are no entries here.
return {
  {
    id = "debugging.performance-startup",
    title = ":Debug performance startup [runs] starts a headless Neovim under --startuptime per run and shows the total and the slowest scripts",
    surface = { "command:Debug performance startup" },
    docs = "README.md",
  },
  {
    id = "debugging.proc-trace",
    title = ":Debug proc start|stop|log logs the duration of every system()/jobstart()/vim.system() call and opens the log",
    surface = {
      "command:Debug proc start",
      "command:Debug proc stop",
      "command:Debug proc log",
      "command:Debug proc status",
    },
    docs = "README.md",
  },
  {
    id = "debugging.proc-watch",
    title = ":Debug proc watch [seconds] runs the bundled PowerShell process watcher in a terminal split (Windows; elsewhere a hint)",
    surface = { "command:Debug proc watch" },
    docs = "README.md",
  },
  {
    id = "debugging.messages-capture",
    title = "<lt>c / :Debug messages capture writes :messages to a log file and to the system clipboard (an OS tool when the + register has no provider)",
    surface = {
      "command:Debug messages capture",
      "config:views.keymaps.capture",
      "config:views.keymaps.capture_clipboard",
    },
    docs = "README.md",
  },
}
