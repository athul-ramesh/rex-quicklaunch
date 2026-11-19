# rex-quicklaunch

Quick Launch picks one command from your JSON list in the Rex command palette and runs it in a floating terminal.

## Install

You need a Rex server and a Rex app that can show `rex.ui.pick`. Custom UI arrived in control API revision 17.

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

Focus a terminal pane when the command uses the focused directory.

Press the bound key, or choose **Quick Launch…** in the command palette.

Choose a row. Press Esc to cancel.

Rex focuses a new floating terminal and runs the command there. The working directory comes from `cwd.policy`. When `keep_open` is false, the float closes after the command exits. When `keep_open` is true, the float stays open after the command exits.

To run one launch with no palette prompt, from a live session:

```bash
rex do -s "$REX_SESSION" rex_quicklaunch name=htop
```

`name` is that launch's `name`.

## What a launch does

The list is the command palette. Every launch opens one floating terminal.

Older versions of this plugin opened an fzf list in a floating pane. Enter either replaced that pane with the command, or opened a second float when `new_pane` was true. Config files from that version still load. `new_pane` is accepted and ignored, because there is no picker pane left to replace or dismiss.

`keep_open` false sets `exit.on_completion`, and the float closes when the command exits. `keep_open` true leaves the float open. A command that exits very quickly also leaves the float open, and the output stays on screen. The old "Press Enter to close" step is gone.

`cwd.policy` `focused` uses the focused terminal's directory at the moment you confirm the row. `fixed` uses `cwd.path`, and a leading `~` expands to your home directory. `home` uses your home directory.

`argv` runs with no shell. When the first argument contains no `/`, Rex looks it up on `PATH`, then in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, and the Rex Server executable directory. When the first argument contains `/`, it is a file path. An absolute path is used as given. A relative path is resolved from the working directory. Shell startup files are not loaded. The float receives that same directory list as `path_prepend`, so programs the command starts can be found the same way.

## Config

The config file is `~/.config/rex/quicklaunch.json`. The sample is `quicklaunch.example.json`.

| Field | Meaning |
| --- | --- |
| `version` | The number `1`. |
| `launches` | Array of launch objects, in palette order. |
| `name` | Required. Unique. Row title, and the id the palette returns. |
| `label` | Optional second line on the row. |
| `argv` | Required. Non-empty array of non-empty strings. |
| `cwd.policy` | `focused`, `fixed`, or `home`. |
| `cwd.path` | Required for `fixed`. Not allowed for `focused` or `home`. |
| `keep_open` | Optional boolean. Default false. |
| `new_pane` | Optional boolean. Accepted and ignored. |

A missing file, invalid JSON, an unknown key, a missing working directory, or a missing command fails the action with an error. Cancelling the palette does nothing.

## Check

```bash
luac -p lua/rex_quicklaunch.lua
lua test/quicklaunch_test.lua
```

Load the module from `init.lua` with `require("rex_quicklaunch")`. Run it from a live session with `rex do rex_quicklaunch`.
