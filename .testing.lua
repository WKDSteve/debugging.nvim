-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "debugging",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process. TESTS/sheets_spec.lua is busted style: each feature
  -- sheet is a case of its own named `sheet:<id>`, the name `testing sheets report` finds its result by.
  dialect = { ["TESTS/sheets_spec.lua"] = "busted", ["*"] = "h" },
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "file",
  -- Guards (docs/GUARDS.md of testing.nvim): the suite is clean under every one of them with the
  -- per-file isolation above (setup() state, plugin-owned log/capture dirs and the clipboard job
  -- die with the child), so all of them fail the run.
  guards = {
    fs = "error",
    state = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    process_net = "error",
  },
  -- The runner counts which commands, keymaps and autocommands the specs exercise (docs/SURFACE.md of testing.nvim);
  -- `scripts/test.sh surface` compares that with surface.baseline.json (a regression gate, not a percentage).
  surface = { track = true },
  -- The keymaps live under views: `views.keymaps = false` (same as `{ enable = false }`) registers none.
  conformance = {
    -- gated: a failed check makes `scripts/test.sh conformance` exit 1
    gate = true,
    keymaps_off = { views = { keymaps = false } },
  },
  -- No spec spawns a foreign executable or opens a socket, and writes below the child's own stdpath() sandbox are
  -- not findings. The one spawn is TESTS/sheets_spec.lua's: each feature sheet runs in a child editor (`nvim`); what
  -- that editor starts (a headless nvim, pwsh, the clipboard stand-ins) is the sheet's, not the spec's.
  guard_allow = { fs = {}, spawn = { "nvim" }, network = {} },
  -- The pipeline is derived (`scripts/test.sh ci list`). The GitHub workflow is generated from `workflow`:
  -- `testing init --workflow=public --force` writes it (testing.nvim docs/WORKFLOW-CI.md), the step
  -- workflow-in-sync checks it.
  ci = {
    workflow = {
      name = "debugging.nvim",
      layout = "hosted",
      -- the steps that depend on the platform: the windows and macOS legs run only these
      platform = { "suite", "conformance" },
      -- `testing ci land`: a check branch ci/** runs the hosted legs, main moves to a commit only once it is green there
      land = true,
    },
    steps = {
      ["workflow-in-sync"] = { preset = "workflow-in-sync" },
    },
  },
}
