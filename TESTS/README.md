# Tests

Headless spec suite for debugging.nvim.

Most of this plugin is UI side effects (scratch windows, notifications), which
is why testing was deferred for a long time. What *is* worth testing is the
layer underneath: the text parsers in `autocmds/sources.lua`, the argument
handling in `commands.lua` and the config merge — all pure or nearly pure, and
all places where a silent wrong answer is plausible.

## Run

From the repo root:

```sh
bash scripts/test.sh                 # every spec
bash scripts/test.sh --file config   # only spec files whose name contains "config"
bash scripts/test.sh --json ir.json  # also write the machine-readable result
```

The suite is run by [testing.nvim](https://github.com/WKDSteve/testing.nvim)
(configured in `.testing.lua`, dialect `h`: the specs run on `TESTS/harness.lua`).
It prints one line per spec and exits non-zero if any spec failed
(`DEBUGGING_TESTS_OK` on success).

[lib.nvim](https://github.com/WKDSteve/lib.nvim) is a hard dependency —
every module requires `lib.nvim.notify` at load time. `scripts/test.sh` looks
for it (and for testing.nvim) in `$LIB_NVIM_DIR` / `$TESTING_NVIM_DIR`, then
`.deps/<name>`, then `../<name>`, then the lazy.nvim install dir, and exits 1
naming all four places if one is missing.

## Layout

| File                        | Covers                                                                                                                                                                             |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `harness.lua`                 | Shared assertions (`eq`, `ok`, `match`, `eq_list`) plus `scratch()`, `tmpfile()` and `realpath()` helpers.                                                                                         |
| `config_spec.lua`             | `config/init.lua`: DEFAULTS merge, partial overrides, `all = true`, DEFAULTS immutability.                                                                                           |
| `init_spec.lua`               | `init.lua`: `setup()`'s idempotency guard, `features.views` gating `views.setup()`, `bindings.setup()` always running.                                                               |
| `sources_spec.lua`            | `autocmds/sources.lua`: `normalize_events`, `read_brace_block`, `parse_args`, completion, and an end-to-end scan over a temp tree.                                                    |
| `startup_spec.lua`            | `tools/startup.lua`: `--startuptime` log parsing (total, per-script entries, fallback to max clock).                                                                                 |
| `commands_spec.lua`           | `commands.lua`: dispatch, feature gating, buffer/window id validation, two-level completion.                                                                                         |
| `handle_args_spec.lua`        | Composer argtypes on handle-taking actions: window/buffer/path completion, and the deliberately-generic slots (`proc`, `performance startup`).                                       |
| `actions_spec.lua`            | `actions/module_reload.lua` (path -> module name -> reload, end to end), `actions/neotree_safety.lua` (the injectable table/module-name bridge, every helper), `actions/reports.lua` (win id validation). |
| `filetree_spec.lua`           | `actions/filetree.lua`: the three reports of `:Debug filetree` against a stand-in for `require("filetree").fs_state()` (handles with askers and errors, the counters, quarantined / changed / reading, released handles, what a handle covers in each watch mode), a tree that holds nothing, the own tree not being the active backend, a state with fields missing, the degradation without filetree.nvim (which is never loaded to ask it), with one that has no `fs_state` and with one whose `fs_state` fails, and the command (completion, dispatch, `features.filetree = false`). |
| `autocmds_runtime_spec.lua`   | `autocmds/runtime.lua`: event/pattern defaulting, the empty-result and invalid-event branches, group/command/desc/callback rendering.                                               |
| `nvim_options_spec.lua`       | `nvim_options/indent_helpers.lua`: the option report and the treesitter-indent toggle (enable/disable/default).                                                                      |
| `keylogger_spec.lua`          | `terminals/keylogger.lua`: logfile resolution precedence, the file lifecycle, start/stop guard warnings, the unopenable-logfile error path.                                          |
| `tools_spec.lua`              | `tools/buffer_inspector/init.lua`, `tools/cursor/state.lua`, `tools/vardump/init.lua`, and `tools/proc_trace.lua`'s argument parsing (stubbed against a fake `proc_trace` tracer).    |
| `markdown_spec.lua`           | `markdown/inline_debug.lua`: `gather()` end to end against a real buffer, `open_log()`, a pinned regression for the mkdir/path bugs found while writing this suite, and the core `vim.treesitter` info without nvim-treesitter (plugin absent, a stubbed main-branch `nvim-treesitter.parsers` without `has_parser`/`get_parser`, an unknown and an empty filetype, a read-only probe that creates no parser -- spied on `vim.treesitter._create_parser` -- and reports the language a highlighter actually runs, and a composite filetype with 0.9's `get_lang()` simulated). |
| `bindings_spec.lua`           | `bindings/init.lua`'s `features.views` gate, `bindings/keymaps.lua`'s action wiring (driven through a real `lib.nvim.bindings.keymap` registration), the proof that the retired views autocmds (WinEnter/BufWinEnter refresh, FileType close) are gone, and `bindings/usercmds.lua`'s `DBG_AUTOCMD_EXPR` argtype via the real `:Debug` command. |
| `views_spec.lua`              | `views/init.lua`'s setup/getter merge logic, `views/display.lua`'s `clear_all`/tag lookups, `views/capture/clipboard/init.lua` (stubbed). |
| `views_recent_spec.lua`       | `views/recent.lua`: filter -> `lib.nvim.messages.snapshot()` levels mapping (all/non_error/error), the real fallback branch (ui.kit genuinely absent from this suite's rtp) vs. a stubbed `ui.kit.message_log` path, window-tag reuse (focus instead of reopening), the live `on_message` listener respecting the filter, `load_more` wiring, and unsubscribe-on-close. Both `lib.nvim.messages` and `debugging.views` are stubbed -- their own logic has its own suites (lib.nvim, `views_spec.lua`). |
| `capture_spec.lua`            | `views/capture/init.lua`: every Noice retrieval strategy (manager/history/buffer/api.status, each faked), the real `:messages` fallback, the empty-content guard, and the save_file/clipboard sinks. |
| `health_spec.lua`             | `health.lua`: regression guards for the composer pre-flight crash (see below) and the "recent popup" section (ui.kit live vs static, attach state and its cause via `lib.nvim.messages.status()`, missing store, throwing status, which entries the section holds, no advice on info()), the externals noice line (probed without `require`) -- not full coverage of the reporter, see "Deliberately left untested".        |
| `minimal_init.lua`            | Runtimepath for child runs: this plugin plus testing.nvim and lib.nvim; fatal when a dependency is missing.                                                                          |

## Coverage

Every `lua/debugging/**/*.lua` file with real logic or branching now has a
dedicated real-assertion suite (or a section of one): config merge, the
`autocmds sources`/`autocmds runtime` parsers and reporters, the `:Debug`
dispatch/completion/overview layer, the composer route builder and its
argtypes, every keymap/usercmd/autocmd binding, the views subsystem's
setup/getter merge logic and window focus/scroll primitives, the Noice/
`:messages` capture pipeline (every retrieval strategy, faked), the
clipboard/file sinks, the actions layer (module reload, the neotree safety
bridge, buf/tab/win reports), the tools layer (buffer/window/tab inspector,
cursor state, vardump, proc_trace's argument parsing), the terminal keylogger,
and the indent helpers.

Five real bugs surfaced (two while writing this pass, one more in a
2026-09-18 re-audit, two from the 2026-10-30 nvim-treesitter API check and
its review), and all five are now fixed:

- **Fixed: `markdown/inline_debug.lua`'s `M.gather()` could crash outright.**
  It called `vim.fn.mkdir(debugfolder)` without the `"p"` (parents) flag. On
  any machine where `stdpath("data")/debuglog` does not already exist (a
  fresh profile, or simply never having run `:Debug markdown inline` before),
  that raises an uncaught `E739` instead of returning `0` — crashing the
  command instead of degrading gracefully, and unlike almost every other
  `mkdir` call in this codebase, this one wasn't `pcall`-guarded either. Now
  passes `"p"`, matching `terminals/keylogger.lua`'s equivalent call.
- **Fixed: `markdown/inline_debug.lua`'s log file was never written into the
  directory `M.gather()` just created.** `out_path` used to be built as
  `debugfolder .. "_debuglog_" .. ts .. ".log"` — no path separator between
  `debugfolder` (`.../debuglog/markdown_inline`) and the suffix — so the
  actual file landed as a *sibling* of that directory
  (`.../debuglog/markdown_inline_debuglog_<ts>.log`), not inside it, leaving
  the `mkdir`'d `markdown_inline/` directory permanently empty. Now built via
  `lib.nvim.fs.path`'s `joinpath({ debugfolder, "debuglog_" .. ts .. ".log" })`,
  matching the join convention already used by `views/capture/init.lua`, so
  the log lands at `.../debuglog/markdown_inline/debuglog_<ts>.log`.
  `markdown_spec.lua` now asserts the corrected layout.
- **Fixed: `health.lua`'s composer pre-flight could crash `:checkhealth`
  outright.** Its last section called
  `require("lib.nvim.bindings.usercmd.composer").checkhealth("Debug")`
  unguarded — even though the module-resolution section a few lines above it
  already probes that exact module via `check_require(..., "error", ...)`
  and would already have reported it missing. If composer really is
  unavailable, that bare `require` raised an uncaught Lua error instead of
  degrading to the warning already issued, which also meant every section
  after it (`neotree`, `proc`) never ran and `:checkhealth` showed a raw
  traceback instead of a graceful report. Now `pcall`-guarded, falling back
  to `vim.health.warn(...)` pointing back at the module-resolution error.
  `health_spec.lua` pins the fix with composer forced missing via a scoped
  `require` swap.
- **Fixed (2026-10-30): `markdown/inline_debug.lua`'s Tree-sitter info
  silently reported no parser.** `collect_treesitter_info` called
  `nvim-treesitter.parsers.has_parser`/`get_parser`, which the
  nvim-treesitter main-branch rewrite dropped, so `has_parser` and
  `parser_attached` came back `false` even with a working markdown parser.
  It now uses the core API (`vim.treesitter.language.get_lang`/`add`/
  `inspect`) and no longer needs nvim-treesitter at all. `markdown_spec.lua`
  pins it: no plugin, a stubbed main-branch `parsers` module, and an unknown
  filetype.
- **Fixed (2026-10-30, review): the Tree-sitter info created the state it
  reported.** The first core-API version probed `parser_attached` with
  `vim.treesitter.get_parser()`, which creates a parser and attaches it to the
  buffer (`nvim_buf_attach`) when there is none, and replaces a cached parser
  of another language. So `parser_attached` was always equal to
  `has_parser`, gathering left a parser on buffers where Tree-sitter never
  ran, and a buffer highlighted with an explicit language lost its cached
  parser. `parser_attached` is now read from the highlighter registry
  (`vim.treesitter.highlighter.active`, via `package.loaded`) and the new
  `attached_lang` names the language that actually runs. Also: a composite
  filetype on 0.9 (whose `get_lang()` returns nil for unregistered
  filetypes) now probes its main language, like 0.10+. `markdown_spec.lua`
  pins both: no `_create_parser` call while probing, a `c` buffer without
  Tree-sitter, a `c` buffer highlighted as `lua`, and a stubbed 0.9
  `get_lang()`.

A few more real quirks came up and are pinned as ordinary (non-`BUG:`)
assertions, documenting behaviour that is surprising but not wrong enough to
justify changing without the author's input:

- **`tools/vardump/init.lua`'s word-under-cursor uses `%w+`** (alnum only, no
  underscore). On a snake_case identifier like `hello_from_cursor`, `:Debug
  dump` with the cursor on it only grabs `hello` — silently dumping a
  different, truncated global instead of erroring or dumping the right one.
- **`views/capture/init.lua`'s `capture_messages()` reports failure when
  content was actually captured**, if the caller passes both
  `save_file = false` and `clipboard = false`: since neither sink ran,
  `#success_operations > 0` is false regardless of whether the message
  content itself was retrieved successfully. No real caller in this repo
  triggers it (every keymap and `debug_helper.test_capture()` requests at
  least one sink), but a direct Lua call asking for neither would see
  `ok = false` alongside real `content`.
- **`views/init.lua`'s `M.setup()` resets keymaps/recent on every call.**
  Like `config/init.lua`'s `setup()`, it rebuilds `keymaps` and `recent` from
  their defaults each time; only `capture.base_dir` (module state on
  `views.capture`) persists across calls.

### Deliberately left untested

- **`lua/debugging/@types/init.lua`, `autocmds/@types/init.lua`,
  `bindings/@types/init.lua`, `markdown/@types/init.lua`, `tools/@types/init.lua`,
  `views/@types/init.lua`** — `---@meta` type-anchor files that `return {}`;
  no runtime behavior to test.
- **`health.lua`** — a declarative `:checkhealth` reporter: each line maps a
  runtime probe (an external binary on PATH, an optional plugin, a write
  permission check) straight to one `vim.health.*` call. Exercising every
  branch would mean mocking every external it probes and mostly asserting
  "the right `vim.health.*` method got called with the right string" — testing
  the mocks more than the code, for a module whose failure mode (a wrong
  hint in `:checkhealth`) has no functional blast radius. The one exception
  is `health_spec.lua`'s narrow regression guard for the composer-crash bug
  above — a real behaviour defect, not a declarative-reporter detail, so it
  gets a real assertion instead of staying unguarded like the rest of this
  file.
- **`views/debug_helper.lua`** — confirmed dead code: its own header already
  flags "no caller anywhere in this repo (only self-referenced in its own
  report text)". Not wired into `:Debug`, not required by anything else in
  `lua/debugging/`. Left untested rather than given a suite for unreachable
  code; worth a follow-up removal decision from the author (see the report
  this suite's PR/commit was written against).
- **`views/init.lua`'s `windows_clear`/`messages_capture`** — one-line
  delegators to `views.display`/`views.capture`. What they call into
  (`display.clear_all`, `capture.capture_messages`, and the same
  capture-then-notify pattern already exercised through
  `bindings/keymaps.lua`'s `capture_to` closure) is what's actually tested.
  `messages_show`/`noice_all`/`noice_errors` moved to `views/recent.lua`
  (`recent.show("non_error"|"all"|"error")`) and **are** tested now, in
  `views_recent_spec.lua` — unlike the old `vim.cmd("Noice errors")` direct
  call, nothing here hard-requires Noice to be installed to run safely.
- **`tools/proc_trace.lua`'s `M.watch()`** — spawns a real terminal split
  running an external PowerShell script against the live process tree
  (Windows-only). Every other `proc_trace` action is exercised in
  `tools_spec.lua` against a faked `lib.nvim.system.proc_trace`; `watch()`'s
  own dispatch logic (the win32 gate, `find_watch_script`, the pwsh/powershell
  choice) is all real side effects with nothing pure to isolate.
- **`tools/startup.lua`'s `measure_once`/`M.startup`** — spawns real
  headless Neovim subprocesses to benchmark. `M.parse()`, the pure log
  parser both call into, is fully covered in `startup_spec.lua`.
- **`views/capture/init.lua`'s Noice buffer-scan and `api.status` fallbacks
  (Methods 3/4)** — actually are covered directly in `capture_spec.lua`
  (faked `noice://` buffers and a faked `noice.api.status`); noted here only
  because they're easy to assume are skipped along with the rest of the
  Noice surface. What's *not* covered is Noice's real message-object shape,
  since Noice itself isn't a dependency of this suite — every shape is
  a best-effort fake of what `extract_noice_text` documents handling.

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.match` / `H.eq_list`); testing.nvim discovers every `*_spec.lua` under
`TESTS/` by itself. Compare paths with `H.realpath()` on both sides rather than
`vim.fs.normalize`, which does not resolve the macOS `/var` symlink.

Two conventions worth keeping:

- **Stub `vim.notify` when asserting on user-facing messages**, and restore it
  in all paths (`pcall` around the body) — an unrestored stub silently breaks
  every later spec.
- **Prefer asserting on the reason, not just the effect.** `commands_spec`
  checks that an invalid id produces *"invalid window id"*, because the bug it
  guards against was a dispatch that did something plausible-looking instead of
  refusing.

## Testing the tests

A spec that cannot fail is worse than no spec. When adding one, break the code
it covers on purpose once and confirm the suite goes red. The id-validation
assertions in `commands_spec` were verified that way: with the check disabled,
`:Debug report win abc` falls back to reporting all windows, which is exactly
the regression the spec now pins down.
