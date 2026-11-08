# rex-quicklaunch

Floating fzf picker for CLI commands you define in JSON. One Rex shortcut opens the list in a pane; Enter runs the highlighted command in that same pane.

## Dependencies

- [Rex](https://rex.dev) server running
- `fzf` (`brew install fzf`)
- Python 3 (stdlib only in the helper)

## Install

```bash
mkdir -p ~/.config/rex
ln -sf "$(pwd)/lua/rex_quicklaunch.lua" ~/.config/rex/rex_quicklaunch.lua
ln -sf "$(pwd)/bin/rex-quicklaunch" ~/.config/rex/rex-quicklaunch
chmod +x bin/rex-quicklaunch
cp quicklaunch.example.json ~/.config/rex/quicklaunch.json
```

Edit `~/.config/rex/quicklaunch.json` for your tools.

Optional paths:

```bash
export REX_QUICKLAUNCH_HELPER=/path/to/rex-quicklaunch
export REX_QUICKLAUNCH_CONFIG=/path/to/quicklaunch.json
```

Add to `~/.config/rex/init.lua`:

```lua
require("rex_quicklaunch")
rex.bind("cmd+shift+g", "rex_quicklaunch")
```

Reload:

```bash
rex config reload
```

## Usage

Focus a terminal pane and press your binding, or run **Quick Launch…** from the command palette. Enter runs the selected launch. Esc cancels and closes the helper.

From a live session:

```bash
rex -C "Mac mini" do -s "$REX_SESSION" rex_quicklaunch
```

Press the shortcut again while the float is open to raise and focus the existing picker (the in-memory fzf state is unchanged; focused cwd was captured when the pane was created).

## Config

`~/.config/rex/quicklaunch.json` (see `quicklaunch.example.json`):

| Field | Meaning |
| --- | --- |
| `version` | Must be `1` |
| `name` | Row title in fzf |
| `argv` | Argument vector exec’d without a shell |
| `cwd.policy` | `focused` (pane dir at open time), `fixed` (`cwd.path`, `~` expanded), or `home` |
| `keep_open` | In-picker behavior when `new_pane` is false; with `new_pane: true`, maps to Rex `exit.on_completion` (see below) |
| `new_pane` | If true, open the command in a new floating pane and close this picker (default false) |
| `label` | Optional extra column in the fzf row |

`keep_open: false` replaces the helper process with the program (`execve`). `keep_open: true` runs the command in the picker and leaves output visible until you press Enter.

With `new_pane: true`, Enter opens a separate floating pane for the command and dismisses the quick-launch picker. `keep_open: false` closes that pane when the command exits (`exit.on_completion`); `keep_open: true` keeps it open after exit so you can read output (same idea as an agent session).

Launched programs inherit PATH with missing `~/.local/bin`, Homebrew, and system fallback directories appended, so tools such as `claude` or Neovim can resolve without a login shell. Commands run directly without loading shell startup files; custom PATH entries from your shell configuration require launching through that shell explicitly.

## Development

```bash
python3 -m py_compile bin/rex-quicklaunch
python3 bin/rex-quicklaunch --help
REX_QUICKLAUNCH_CONFIG="$(pwd)/quicklaunch.example.json" \
  python3 bin/rex-quicklaunch --validate-config
```

Check Lua syntax (when `luac` is available):

```bash
luac -p lua/rex_quicklaunch.lua
```

Do not load `lua/rex_quicklaunch.lua` with `rex do … --action` on the module table. Use `require("rex_quicklaunch")` in `init.lua`, then `rex do rex_quicklaunch` from a live session.
