# Arena grounding: ship-next launch features

## Goal
Extend rex-quicklaunch so a launch can choose float vs split placement, reuse an existing pane by name, register a keybind from JSON, prompt for arguments, and pass `initial_input` into the terminal. One coherent config + runtime model. Do not implement code in this arena. Produce a design artifact only.

## Current system (main)
- Single module: `lua/rex_quicklaunch.lua`
- Config: `~/.config/rex/quicklaunch.json` version 1
- Launch fields today: `name`, `argv`, `cwd` (`focused`|`fixed`|`home`), `keep_open`, `label`, ignored `new_pane`
- Flow: load JSON → pick (or `args.name`) → resolve cwd → resolve argv on PATH → `rex.session.new_layer` float with fixed `BOUNDS` → focus → deferred reclaim focus after palette
- Action: `rex_quicklaunch` with `args = { name = "string?" }`
- Tests: `test/quicklaunch_test.lua` (parse + open with mocked `rex`)
- Docs: `README.md`, sample `quicklaunch.example.json`

## Operator reality
Live launches include TUIs and agents (`claude`, `devin`, `pi` with `keep_open`). Separate `init.lua` actions open Claude/Devin as right splits. Placement and reuse should absorb that duplication.

## Rex facts (documented)
- `rex.ui.pick` / `rex.ui.input` inside action `run`
- `rex.session.new_layer{ bounds, focus, layout }`
- `rex.session.new_split{ anchor_id, direction, side, focus, layout }`
- Terminal options: `command`, `shell`, `cwd`, `initial_input`, `exit`; this plugin also uses `path_prepend`
- `rex.bind(key, action_name, args?)`
- `rex.session.focus_block`, `float_block`, `close_layer`, session view/list APIs may help reuse

## Constraints
- Preserve version-1 config compatibility for existing launches (unknown new keys fail today via strict key lists; design must say how versioning works)
- Keep one float/split per successful open unless reuse finds an existing target
- No fzf return
- Smallest API a future maintainer can extend
- Design only. No Lua edits in candidate worktrees for this arena.

## Candidate output
Write exactly one file:
`<worktree>/.audit/ship-next-design.md`

Required sections:
1. Launch record shape (fields, defaults, illegal combos)
2. Config versioning / migration story
3. `open()` control flow (ordered steps, including prompt and reuse)
4. Reuse identity and lookup (what is stored, where, when cleared)
5. Bind registration lifecycle
6. Test cases to add (names + assertion intent)
7. Rejected alternatives (short)
