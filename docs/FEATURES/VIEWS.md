# Views

`:Debug messages` and `:Debug noice` — a popup over the messages Neovim
showed recently, plus the capture actions that get the `:messages` history out
of the editor and into an issue or a chat.

## Recent-messages popup

`<lt>m`, `<lt>n` and `<lt>e` (and `:Debug messages show`, `:Debug noice
all|errors`) open one popup over one store, with three filters:

| Key | Usercmd | Filter |
| --- | --- | --- |
| `<lt>m` | `:Debug messages show` | non-error entries (trace … warn) |
| `<lt>n` | `:Debug noice all` | everything |
| `<lt>e` | `:Debug noice errors` | errors only |

The `noice` category and the `noice_all` / `noice_errors` keymap names are
kept from the time these keys opened `:Noice` windows; Noice itself is not
needed for the popup. Pressing a key whose popup is already open focuses it
instead of opening a second one; `<lt>x` / `:Debug messages clear` closes all
three.

The entries come from [lib.nvim]'s `lib.nvim.messages` store. On open the
popup shows the last `views.recent.window_s` seconds, topped up to at least
`views.recent.min_entries` entries however old they are, so a quiet minute
does not open an empty popup.

How it renders depends on [ui.nvim]:

- **With ui.nvim** (`ui.kit.message_log`): live and paginated. New messages
  that match the filter are appended while the popup is open, older history
  loads one `window_s` page at a time (quiet stretches are skipped). Each
  message is folded to one header line -- wall-clock time and age, a tag
  (level, Vim error code like `E492`, kind, source) and the title cut to fit;
  `<CR>` unfolds the full text, wrapped to `views.recent.wrap_width`. The keys inside the popup are listed in
  [configuration.md](../configuration.md#keys-inside-the-popup) and under `?`.
- **Without ui.nvim**: a static snapshot in a `lib.nvim.output.viewer`
  window, one notification says so. Multi-line entries (error texts, stack
  traces) are split; the `[Ns ago]` age stands on the first line only.

What the store holds depends on the host config, not on this plugin:
everything sent through `lib.nvim.notify` always, every other message
(`:echomsg`, `:write`, Lua and `E…` errors, `:!cmd` output) only while
`lib.nvim.messages` has its `ext_messages` logger attached — which needs a
running renderer (noice) and a `require("lib.nvim.messages").setup()` call.
See [installation.md](../installation.md#what-feeds-the-recent-messages-popup);
`:checkhealth debugging` reports the current state in its "recent popup"
section.

- **Module:** `views/recent.lua` (`show`), `views/init.lua`
  (`messages_show`, `noice_all`, `noice_errors`, `windows_clear`),
  `views/display.lua` (`clear_all`)
- **Config:** `opts.features.views`, `opts.views.recent` (`window_s`,
  `min_entries`, `order`, `collapsed_default`, `wrap_width`) — see
  [configuration.md](../configuration.md#recent-messages-popup)
- **Usercmds:** `:Debug messages show|clear`, `:Debug noice all|errors` — see
  [BINDINGS.md](../BINDINGS.md#user-commands)
- **Keymaps:** `<lt>m` / `<lt>n` / `<lt>e` / `<lt>x` — see
  [BINDINGS.md](../BINDINGS.md#default-keymaps)

[lib.nvim]: https://github.com/WKDSteve/lib.nvim
[ui.nvim]: https://github.com/WKDSteve/ui.nvim

## Capture to file, to clipboard, or both

`capture_messages` writes the current `:messages` output to a timestamped file
under `opts.views.output_dir` (default: `stdpath("state")/debug_views`),
copies it to the clipboard, or does both.

Three separate keys cover the choice rather than a prefix tree: `<lt>c` for
both, `<lt>f` for file only, `<lt>y` for clipboard only. A `<lt>c`-then-maybe-
`f` tree would make the common case wait to see whether a second key follows,
for the sake of the two rare ones.

- **Module:** `views/capture/init.lua`, `views/capture/clipboard/init.lua`
  (delegates to `lib.nvim.cross.copy_to_clipboard`)
- **Config:** `opts.views.capture`, `opts.views.output_dir`
- **Usercmds:** `:Debug messages capture` (file + clipboard)
- **Keymaps:** `<lt>c` / `<lt>f` / `<lt>y` — see
  [BINDINGS.md](../BINDINGS.md#default-keymaps)

## Individually overridable keymaps

The seven view keymaps are declared through `lib.nvim.bindings.keymap`'s
registry, which is what makes each one overridable on its own. `prefix` used
to be the only lever, so a user who wanted a different key for one view had to
move all seven; `keymaps = { messages = "<leader>dm" }` now moves exactly one,
`= false` drops one, and `prefix` still supplies the default for the rest.
which-key gets a `"Debug"` group label for the prefix from the same
declaration, if it is installed.

- **Module:** `bindings/keymaps.lua` (`M.setup`)
- **Config:** `opts.views.keymaps.enable`, `opts.views.keymaps.prefix`
  (default `"<lt>"`, the literal `<` key), plus one optional key per action —
  see [configuration.md](../configuration.md)
- **Keymaps:** `<lt>m` / `<lt>n` / `<lt>e` / `<lt>c` / `<lt>f` / `<lt>y` /
  `<lt>x` — see [BINDINGS.md](../BINDINGS.md#default-keymaps)

## Removed view options

`opts.views.timings` (`delay_messages_ms`, `delay_noice_ms`, `retry_delay_ms`,
`attempts`, `capture_timeout_ms`) and `opts.views.autocmds` (`enable`,
`group_name`, `auto_refresh`) belonged to the command-output windows the popup
replaced (they waited for `:messages` / `:Noice` to render and re-ran them on
`WinEnter`). Nothing reads them any more, and the plugin registers no
autocommand: they were removed without a grace period, so a config that still
sets one gets the "unknown option" warning at `setup()` (and under
`:checkhealth debugging`) and the key is ignored. Delete it from your config.
