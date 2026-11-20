# rex-quicklaunch

Quick Launch picks one command from your JSON list in the Rex command palette and runs it in a floating or split terminal.

## Install

You need a Rex server and a Rex app that can show `rex.ui.pick`. Custom UI arrived in control API revision 17. Prompts use `rex.ui.input`.

Run these commands from this repository.

```bash
mkdir -p ~/.config/rex
ln -sf "$(pwd)/lua/rex_quicklaunch.lua" ~/.config/rex/rex_quicklaunch.lua
cp quicklaunch.example.json ~/.config/rex/quicklaunch.json
```

Edit `~/.config/rex/quicklaunch.json` and put your commands in `launches`.

When the config file is not `~/.config/rex/quicklaunch.json`, set `REX_QUICKLAUNCH_CONFIG` to its path.

Add this to `~/.config/rex/init.lua`.

```lua
require("rex_quicklaunch")
rex.bind("cmd+shift+g", "rex_quicklaunch")
```

Reload Rex.

```bash
rex config reload
```

## Run a launch

Focus a terminal pane when the command uses the focused directory. Split placement needs a focused block in the session.

Press the bound palette key, a per-launch `key` chord, or choose **Quick Launch…** in the command palette.

Choose a row. Press Esc to cancel. Cancelled prompts also stop the action.

Rex runs the command in a new pane or focuses an existing one when `reuse` is true. The working directory comes from `cwd.policy`. When `keep_open` is false, the pane closes after the command exits. When `keep_open` is true, the pane stays open after the command exits.

To run one launch with no palette prompt, from a live session:

```bash
rex do -s "$REX_SESSION" rex_quicklaunch name=htop
```

`name` is that launch's `name`.

## What a launch does

The list is the command palette. Every launch opens one pane unless `reuse` finds an existing terminal block whose label matches `name`.

`place` chooses geometry. The default `float` opens a floating layer. `left`, `right`, `up`, and `down` split beside the focused block. Splits ignore `bounds`.

`reuse` true looks up terminal shell blocks by label before prompts or create. One match focuses that pane. More than one match fails. Zero matches continues to create.

`key` registers a chord at load time that opens that launch without the palette. Duplicate keys across launches are rejected when the file loads.

`prompt` asks for values in order before create. Each answer replaces every `{{id}}` token in `argv` and `initial_input`. Cancelled input stops the action. Reuse hits skip prompts.

`initial_input` is sent to the new terminal only on create, not on reuse.

Older versions of this plugin opened an fzf list in a floating pane. Enter either replaced that pane with the command, or opened a second float when `new_pane` was true. Config files from that version still load. `new_pane` is accepted and ignored, because there is no picker pane left to replace or dismiss.

`keep_open` false sets `exit.on_completion`, and the pane closes when the command exits. `keep_open` true leaves the pane open so you can read the output. The old "Press Enter to close" step is gone.

`cwd.policy` `focused` uses the focused terminal's directory at the moment you confirm the row. `fixed` uses `cwd.path`, and a leading `~` expands to your home directory. `home` uses your home directory.

`argv` runs with no shell. When the first argument contains no `/`, Rex looks it up on `PATH`, then in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, and the Rex Server executable directory. When the first argument contains `/`, it is a file path. An absolute path is used as given. A relative path is resolved from the working directory. Shell startup files are not loaded. The pane receives that same directory list as `path_prepend`, so programs the command starts can be found the same way.

## Config

The config file is `~/.config/rex/quicklaunch.json`. The sample is `quicklaunch.example.json`.

| Field | Meaning |
| --- | --- |
| `version` | The number `1`. |
| `launches` | Array of launch objects, in palette order. |
| `name` | Required. Unique. Row title, block label on create, and reuse identity. |
| `label` | Optional second line on the palette row. |
| `argv` | Required. Non-empty array of non-empty strings. May contain `{{id}}` tokens when `prompt` is set. |
| `cwd.policy` | `focused`, `fixed`, or `home`. |
| `cwd.path` | Required for `fixed`. Not allowed for `focused` or `home`. |
| `keep_open` | Optional boolean. Default false. |
| `new_pane` | Optional boolean. Accepted and ignored. |
| `place` | Optional. `float` (default), `left`, `right`, `up`, or `down`. |
| `bounds` | Optional float geometry `{ x, y, w, h }` in `(0, 1]`. Only with `place` `float`. Default `0.25, 0.15, 0.5, 0.7`. |
| `reuse` | Optional boolean. Default false. Focus an existing pane with the same block label before create. |
| `key` | Optional chord string. Unique in the file. Registers `rex.bind` when the module loads. |
| `prompt` | Optional array of `{ id, title, placeholder?, default?, required? }`. Answers substitute `{{id}}` in `argv` and `initial_input`. |
| `initial_input` | Optional string sent to the terminal on create only. May use `{{id}}` tokens. |

A missing file, invalid JSON, an unknown key, a missing working directory, or a missing command fails the action with an error. Cancelling the palette or a prompt does nothing.

## Check

```bash
luac -p lua/rex_quicklaunch.lua
lua test/quicklaunch_test.lua
```

Load the module from `init.lua` with `require("rex_quicklaunch")`. Run it from a live session with `rex do rex_quicklaunch`.