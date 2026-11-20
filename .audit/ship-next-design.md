# Ship-next launch design (synthesized)

Base: arena candidate-2. Grafts noted in `.audit/ship-next-synthesis.md`.

A launch is one named command. The palette, `args.name`, or a key from that same record opens it. `open` focuses the pane whose block label is already that name, or creates one pane.

## Launch record shape

The loader rejects unknown keys. It stores the fields below. Later steps trust the record.

| Field | Default when omitted | Parsed value |
| --- | --- | --- |
| `name` | Required. | Non-empty string. Unique in the file. No tab, newline, or NUL. Palette id, palette title, and the block label written at create time. |
| `argv` | Required. | Non-empty array of non-empty strings. No NUL. Placeholder tokens stay in the record until a prompt answers. |
| `cwd` | Required. | `focused`, `fixed` plus `path`, or `home`. Fixed `path` is required for `fixed` and rejected for the other policies. `~` expands on a fixed path. |
| `keep_open` | `false` | Boolean. `false` sets `exit.on_completion` true. |
| `label` | Absent. | Palette subtitle. An empty string is omitted. The block label is `name`. |
| `new_pane` | Absent. | A boolean is accepted and then omitted. The record has no `new_pane` field. |
| `place` | `float` | `float`, `left`, `right`, `up`, or `down`. |
| `bounds` | Module default float bounds | Object `{ x, y, w, h }` of numbers in `(0, 1]`. Allowed only when `place` is `float` (or omitted, which means float). Rejected when `place` is a split direction. Omitted → `{ x = 0.25, y = 0.15, w = 0.5, h = 0.7 }`. |
| `reuse` | `false` | Boolean. |
| `key` | Absent. | Chord string, or nil. |
| `prompt` | Empty array. | Array of prompt objects, in ask order. |
| `initial_input` | Nil. | String, or nil. An empty string is omitted. Newlines are allowed. NUL is rejected. |

`place` is the only split-geometry field. Direction is the axis of the new pane. Side `after` means right when the direction is `horizontal`, and down when the direction is `vertical`. Side `before` means left or up.

| `place` | Rex call | `direction` | `side` |
| --- | --- | --- | --- |
| `float` | `rex.session.new_layer` |  |  |
| `left` | `rex.session.new_split` | `horizontal` | `before` |
| `right` | `rex.session.new_split` | `horizontal` | `after` |
| `up` | `rex.session.new_split` | `vertical` | `before` |
| `down` | `rex.session.new_split` | `vertical` | `after` |

A float uses `bounds` (default above). A split passes `anchor_id = ctx.block_id` and `focus = true`. The call has no ratio and no other anchor.

A prompt object has these fields.

| Field | Default | Rule |
| --- | --- | --- |
| `id` | Required. | Matches `[A-Za-z_][A-Za-z0-9_]*`. Unique inside the launch. |
| `title` | Required. | Non-empty string. Spaces are allowed. Tabs, newlines, and NUL are rejected. `rex.ui.input` uses it as the title. |
| `placeholder` | Nil. | String. An empty string is omitted. The dialog receives it when set. |
| `default` | Nil. | String prefill for `rex.ui.input` `value`. An empty string is omitted. |
| `required` | `true` | Boolean. `true` rejects an empty answer. `false` substitutes the empty string. |

Substitution replaces the exact token `{{id}}`, braces included. The same token may appear in `argv` and in `initial_input`. One answer fills every copy. A token carries no escape sequence.

### Parse rejects

Unknown keys fail, including unknown keys inside `cwd`, `bounds`, and inside a prompt object. Messages keep the current `rex_quicklaunch:` prefix, the launch index, and the name.

The loader rejects the file in these cases.

- `version` is not the number 1.
- `place` is present and is outside the five names.
- `bounds` is present when `place` is `left`, `right`, `up`, or `down`.
- `bounds` is present and is not an object with exactly `x`, `y`, `w`, `h` as numbers in `(0, 1]` whose box fits in the unit square (`x + w <= 1`, `y + h <= 1`).
- `reuse` is present and is not a boolean.
- `key` is present and is empty, has leading or trailing whitespace, or contains a space or an ASCII control character.
- Two launches share a `key`. The message contains `duplicate key`.
- `prompt` is present and is not an array, or an entry lacks a legal `id` and `title`.
- `prompt` is non-empty and some `id` never appears as `{{id}}` in `argv` or `initial_input`. The message contains `unused prompt`.
- `prompt` is non-empty and some `{{` is not exactly `{{` plus a known `id` plus `}}`. The message contains `unknown placeholder`.
- `initial_input` is present and is not a string, or it contains NUL.
- The current `name`, `argv`, `cwd`, `keep_open`, `label`, and `new_pane` rules fail.

An empty `prompt` leaves `{{` in `argv` and `initial_input` as literal text.

These combinations are legal. A launch may set `reuse` with any `place`. It may set `reuse` together with `prompt` and `initial_input`. It may set `key` beside any other field. It may set a split `place` while `cwd.policy` is `home`.

JSON cannot express `direction` or `side`. A chord cannot name a missing launch, because `key` sits on the launch. `new_pane` is omitted before `reuse` is read, so an old `new_pane` true still creates a pane.

### Examples

```json
{
  "name": "Claude",
  "argv": ["claude"],
  "cwd": { "policy": "focused" },
  "keep_open": true,
  "place": "right",
  "reuse": true,
  "key": "cmd+shift+a"
}
```

```json
{
  "name": "notes",
  "argv": ["/bin/zsh"],
  "cwd": { "policy": "home" },
  "keep_open": true,
  "prompt": [{ "id": "line", "title": "First line", "default": "# " }],
  "initial_input": "{{line}}\n"
}
```

```json
{
  "name": "lazygit",
  "argv": ["lazygit"],
  "cwd": { "policy": "focused" },
  "bounds": { "x": 0.1, "y": 0.1, "w": 0.8, "h": 0.8 }
}
```

## Config versioning

Version stays 1. Root keys stay `version` and `launches`. The launch allowlist adds `place`, `bounds`, `reuse`, `key`, `prompt`, and `initial_input`. Omitted fields take the defaults above. Existing files need no edit.

The palette chord stays in `init.lua` as `rex.bind("cmd+shift+g", "rex_quicklaunch")`. A launch `key` opens that one launch.

## open() control flow

Every `open` reads the file again. Key registration runs at module load.

1. Require `ctx.session_id` to be a non-empty string. Otherwise fail. Create nothing.
2. Load and parse the file. Fail on missing file, bad JSON, or parse reject. Create nothing.
3. Choose the name via `args.name` or `rex.ui.pick`. Cancel returns nil.
4. Find the launch by `name`. Unknown name fails.
5. When `reuse` is true, look up panes as below. View error or more than one hit fails and creates nothing. One hit focuses that pane and returns. Prompts, cwd resolution, PATH resolution, create, and `initial_input` stay unused.
6. When `place` is not `float`, require `ctx.block_id` to be a non-empty string. Otherwise fail before any prompt. Create nothing.
7. When `prompt` is non-empty, ask in array order with `rex.ui.input`. Pass `title`, optional `placeholder`, optional `value` from `default`. Cancel returns nil. Empty with `required` true fails. Missing `rex.ui.input` fails naming it.
8. Replace every `{{id}}` in a copy of `argv` and of `initial_input`. Reject a result that contains NUL.
9. Resolve cwd and command with current rules on the substituted argv.
10. Build one terminal layout. Flavor `com.superlogical.terminal.shell`. Block label is `name`. Options: `command`, `cwd`, `shell` `"none"`, `exit.on_completion` from `keep_open`, `path_prepend`, and `initial_input` when the substituted string is present.
11. Create one pane. `float` → `new_layer` with `bounds` and `focus` true. Else → `new_split` with mapped direction/side, `anchor_id = ctx.block_id`, `focus` true.
12. Focus the new block when its id is known. Log focus warnings as today.
13. Schedule deferred float reclaim only for palette-chosen float creates (or palette reuse hits whose layer `kind` is not `tiled`). Named opens and splits skip it.
14. Return `layer_id`, `block_id`, `name`, and `reused` (boolean).

A default record skips steps 5–7. The user sees the palette, then one float.

## Reuse identity and lookup

Identity is `launch.name`. Create writes that string as the layout block label. Lookup compares `block.label` to `launch.name` exactly.

Call `rex.session.view({ session_id = ctx.session_id })` when the API accepts it, otherwise `rex.session.view({})` on the attached session. Walk `windows`, then `layers`, then `blocks`. Keep only blocks whose flavor is `com.superlogical.terminal.shell` (or missing flavor treated as eligible only if label matches and the block is terminal-shaped; prefer explicit flavor when present). A hit keeps `block.block_id`, `layer.layer_id`, and `layer.kind`.

- View nil → fail `cannot list panes`. Create nothing.
- Zero hits → miss. Continue at the prompt step.
- One hit → focus it.
- More than one hit → fail `more than one pane named`. Create nothing.

Focus for one hit: `raise_layer` when `kind` is not `tiled` and the function exists (log and continue on raise error). Then `focus_block`. Focus error fails the action.

Prompts and `initial_input` apply on create only. A hit leaves process input alone.

## Bind registration lifecycle

Inside the existing `rex.action` guard: register the action first. If `rex.bind` is a function, load the config. On load/parse error, log `skipped key bindings` and register no keys. For each launch with `key`, `pcall` `rex.bind(key, "rex_quicklaunch", { name = launch.name })`. Log bind failures and continue. Missing config does not throw on require.

## Test cases

Implement the candidate-2 table, plus:

| Case | Assertion |
| --- | --- |
| `parse_bounds_on_split_rejected` | `place` `right` with `bounds` fails. |
| `parse_bounds_ok_on_float` | Custom bounds parse; open float uses them. |
| `open_prompt_default_prefill` | `ui.input` receives `value` from prompt `default`. |
| `open_reuse_filters_session_and_flavor` | View entries from another session or non-shell flavor are ignored. |

## Rejected (kept from base)

Version 2, root `binds` array, persisted block ids, prompts before reuse hit, injecting `initial_input` on reuse, publishing `direction`/`side` in JSON, fzf return.
