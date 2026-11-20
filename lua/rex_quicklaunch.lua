local M = {}

local BOUNDS = { x = 0.25, y = 0.15, w = 0.5, h = 0.7 }
local TERMINAL_SHELL = "com.superlogical.terminal.shell"
local ICON = "terminal"

local ROOT_KEYS = { version = true, launches = true }
local LAUNCH_KEYS = {
  name = true,
  argv = true,
  cwd = true,
  keep_open = true,
  label = true,
  new_pane = true,
  place = true,
  bounds = true,
  reuse = true,
  key = true,
  prompt = true,
  initial_input = true,
}
local CWD_KEYS = { policy = true, path = true }
local BOUNDS_KEYS = { x = true, y = true, w = true, h = true }
local PROMPT_KEYS = { id = true, title = true, placeholder = true, default = true, required = true }

local PLACE_NAMES = {
  float = true,
  left = true,
  right = true,
  up = true,
  down = true,
}

local PLACE_SPLIT = {
  left = { direction = "horizontal", side = "before" },
  right = { direction = "horizontal", side = "after" },
  up = { direction = "vertical", side = "before" },
  down = { direction = "vertical", side = "after" },
}

local PROMPT_ID_PATTERN = "^[A-Za-z_][A-Za-z0-9_]*$"

local function fail(message)
  error("rex_quicklaunch: " .. message, 0)
end

local function home_dir()
  local home = os.getenv("HOME")
  if type(home) ~= "string" or home == "" then
    return ""
  end
  return home
end

local function expand_user(path)
  local home = home_dir()
  if path == "~" then
    return home
  end
  if path:sub(1, 2) == "~/" then
    return home .. path:sub(2)
  end
  return path
end

local function config_path()
  local raw = os.getenv("REX_QUICKLAUNCH_CONFIG")
  if type(raw) == "string" and raw ~= "" then
    return expand_user(raw)
  end
  local home = home_dir()
  if home == "" then
    fail("HOME is not set, and REX_QUICKLAUNCH_CONFIG is empty")
  end
  return home .. "/.config/rex/quicklaunch.json"
end

local function fallback_dirs()
  local dirs = {}
  local home = home_dir()
  if home ~= "" then
    dirs[#dirs + 1] = home .. "/.local/bin"
  end
  dirs[#dirs + 1] = "/opt/homebrew/bin"
  dirs[#dirs + 1] = "/usr/local/bin"
  dirs[#dirs + 1] = "/usr/bin"
  dirs[#dirs + 1] = "/bin"
  if home ~= "" then
    dirs[#dirs + 1] = home
      .. "/Library/Application Support/com.superlogical.rex"
      .. "/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
  end
  return dirs
end

-- PATH first, then the fallbacks that are not already on it. One list is
-- both the command lookup path and the float's path_prepend.
local function search_dirs()
  local dirs = {}
  local seen = {}
  local function add(dir)
    if type(dir) ~= "string" or dir == "" or seen[dir] then
      return
    end
    seen[dir] = true
    dirs[#dirs + 1] = dir
  end
  local path = os.getenv("PATH")
  if type(path) == "string" then
    for dir in string.gmatch(path, "[^:]+") do
      add(dir)
    end
  end
  for _, dir in ipairs(fallback_dirs()) do
    add(dir)
  end
  return dirs
end

local function rex_test(flag, path)
  -- rex.exec is a callable table in current Rex, and a function is enough too.
  local exec = type(rex) == "table" and rex.exec or nil
  if type(exec) ~= "function" and type(exec) ~= "table" then
    fail("cannot check " .. path .. " (rex.exec is unavailable)")
  end
  local result, err = exec({ "/bin/test", flag, path })
  if result == nil then
    fail("cannot check " .. path .. ": " .. tostring(err))
  end
  return result.ok == true
end

local function is_dir(path)
  return rex_test("-d", path)
end

local function is_executable(path)
  return rex_test("-x", path) and rex_test("-f", path)
end

local function is_list(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" then
      return false
    end
    count = count + 1
  end
  return count == #value
end

local function is_object(value)
  if type(value) ~= "table" then
    return false
  end
  for key in pairs(value) do
    if type(key) ~= "string" then
      return false
    end
  end
  return true
end

local function unknown_key_list(value, allowed)
  local extra = {}
  for key in pairs(value) do
    if allowed[key] ~= true then
      extra[#extra + 1] = tostring(key)
    end
  end
  table.sort(extra)
  return extra
end

local function bad(path, message)
  fail(path .. ": " .. message)
end

local function launch_bad(path, index, name, message)
  local where = "launch " .. tostring(index)
  if name ~= nil then
    where = where .. " (" .. name .. ")"
  end
  bad(path, where .. ": " .. message)
end

local function parse_cwd(entry, path, index, name)
  local cwd = entry.cwd
  if not is_object(cwd) then
    launch_bad(path, index, name, "cwd must be an object")
  end
  local extra = unknown_key_list(cwd, CWD_KEYS)
  if #extra > 0 then
    launch_bad(path, index, name, "cwd unknown keys: " .. table.concat(extra, ", "))
  end
  local policy = cwd.policy
  if policy ~= "focused" and policy ~= "fixed" and policy ~= "home" then
    launch_bad(path, index, name, "cwd.policy must be focused, fixed, or home")
  end
  if policy == "fixed" then
    if type(cwd.path) ~= "string" or cwd.path == "" then
      launch_bad(path, index, name, "cwd.path is required for fixed policy")
    end
    return { policy = "fixed", path = expand_user(cwd.path) }
  end
  if cwd.path ~= nil then
    launch_bad(path, index, name, "cwd.path is not allowed for " .. policy .. " policy")
  end
  return { policy = policy }
end

local function parse_place(entry, path, index, name)
  local place = "float"
  if entry.place ~= nil then
    if type(entry.place) ~= "string" or PLACE_NAMES[entry.place] ~= true then
      launch_bad(path, index, name, "place must be float, left, right, up, or down")
    end
    place = entry.place
  end
  return place
end

local function bounds_in_range(value)
  return type(value) == "number" and value > 0 and value <= 1
end

local function parse_bounds(entry, path, index, name, place)
  if entry.bounds == nil then
    return { x = BOUNDS.x, y = BOUNDS.y, w = BOUNDS.w, h = BOUNDS.h }
  end
  if place ~= "float" then
    launch_bad(path, index, name, "bounds is not allowed when place is a split")
  end
  local bounds = entry.bounds
  if not is_object(bounds) then
    launch_bad(path, index, name, "bounds must be an object")
  end
  local extra = unknown_key_list(bounds, BOUNDS_KEYS)
  if #extra > 0 then
    launch_bad(path, index, name, "bounds unknown keys: " .. table.concat(extra, ", "))
  end
  for _, key in ipairs({ "x", "y", "w", "h" }) do
    if not bounds_in_range(bounds[key]) then
      launch_bad(path, index, name, "bounds." .. key .. " must be a number in (0, 1]")
    end
  end
  if bounds.x + bounds.w > 1 or bounds.y + bounds.h > 1 then
    launch_bad(path, index, name, "bounds must fit in the unit square")
  end
  return { x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h }
end

local function parse_reuse(entry, path, index, name)
  local reuse = false
  if entry.reuse ~= nil then
    if type(entry.reuse) ~= "boolean" then
      launch_bad(path, index, name, "reuse must be a boolean")
    end
    reuse = entry.reuse
  end
  return reuse
end

local function parse_key(entry, path, index, name)
  if entry.key == nil then
    return nil
  end
  local key = entry.key
  if type(key) ~= "string" or key == "" then
    launch_bad(path, index, name, "key must be a non-empty string")
  end
  if key:match("^%s") or key:match("%s$") then
    launch_bad(path, index, name, "key must not have leading or trailing whitespace")
  end
  if key:find(" ") then
    launch_bad(path, index, name, "key must not contain spaces")
  end
  if key:find("%c") then
    launch_bad(path, index, name, "key must not contain control characters")
  end
  return key
end

local function parse_initial_input(entry, path, index, name)
  if entry.initial_input == nil then
    return nil
  end
  local value = entry.initial_input
  if type(value) ~= "string" then
    launch_bad(path, index, name, "initial_input must be a string")
  end
  if value:find("%z") then
    launch_bad(path, index, name, "initial_input must not contain NUL")
  end
  if value == "" then
    return nil
  end
  return value
end

local function valid_prompt_id(id)
  return type(id) == "string" and id:match(PROMPT_ID_PATTERN) ~= nil
end

local function validate_prompt_placeholders(texts, prompt_ids, path, index, name)
  local used = {}
  for id in pairs(prompt_ids) do
    used[id] = false
  end
  for _, text in ipairs(texts) do
    local pos = 1
    while pos <= #text do
      local start = text:find("{{", pos, true)
      if start == nil then
        break
      end
      local rest = text:sub(start + 2)
      local close = rest:find("}}", 1, true)
      if close == nil then
        launch_bad(path, index, name, "unknown placeholder")
      end
      local id = rest:sub(1, close - 1)
      if prompt_ids[id] ~= true then
        launch_bad(path, index, name, "unknown placeholder")
      end
      used[id] = true
      pos = start + 2 + close + 1
    end
  end
  for id, seen in pairs(used) do
    if not seen then
      launch_bad(path, index, name, "unused prompt")
    end
  end
end

local function parse_prompt(entry, path, index, name, argv, initial_input)
  local prompt = {}
  if entry.prompt == nil then
    return prompt
  end
  if not is_list(entry.prompt) then
    launch_bad(path, index, name, "prompt must be an array")
  end
  local seen_ids = {}
  for j, item in ipairs(entry.prompt) do
    if not is_object(item) then
      launch_bad(path, index, name, "prompt[" .. tostring(j) .. "] must be an object")
    end
    local extra = unknown_key_list(item, PROMPT_KEYS)
    if #extra > 0 then
      launch_bad(path, index, name, "prompt[" .. tostring(j) .. "] unknown keys: " .. table.concat(extra, ", "))
    end
    local id = item.id
    if not valid_prompt_id(id) then
      launch_bad(path, index, name, "prompt[" .. tostring(j) .. "] id must match [A-Za-z_][A-Za-z0-9_]*")
    end
    if seen_ids[id] then
      launch_bad(path, index, name, "prompt id must be unique: " .. id)
    end
    seen_ids[id] = true
    local title = item.title
    if type(title) ~= "string" or title == "" then
      launch_bad(path, index, name, "prompt[" .. tostring(j) .. "] title must be a non-empty string")
    end
    if title:find("[\t\n%z]") then
      launch_bad(path, index, name, "prompt[" .. tostring(j) .. "] title must not contain tab, newline, or NUL")
    end
    local required = true
    if item.required ~= nil then
      if type(item.required) ~= "boolean" then
        launch_bad(path, index, name, "prompt[" .. tostring(j) .. "] required must be a boolean")
      end
      required = item.required
    end
    local placeholder = nil
    if item.placeholder ~= nil then
      if type(item.placeholder) ~= "string" then
        launch_bad(path, index, name, "prompt[" .. tostring(j) .. "] placeholder must be a string")
      elseif item.placeholder ~= "" then
        placeholder = item.placeholder
      end
    end
    local default_value = nil
    if item.default ~= nil then
      if type(item.default) ~= "string" then
        launch_bad(path, index, name, "prompt[" .. tostring(j) .. "] default must be a string")
      elseif item.default ~= "" then
        default_value = item.default
      end
    end
    prompt[#prompt + 1] = {
      id = id,
      title = title,
      placeholder = placeholder,
      default = default_value,
      required = required,
    }
  end
  if #prompt > 0 then
    local texts = {}
    for _, part in ipairs(argv) do
      texts[#texts + 1] = part
    end
    if initial_input ~= nil then
      texts[#texts + 1] = initial_input
    end
    validate_prompt_placeholders(texts, seen_ids, path, index, name)
  end
  return prompt
end

local function parse_launch(entry, path, index)
  if not is_object(entry) then
    launch_bad(path, index, nil, "must be an object")
  end
  local extra = unknown_key_list(entry, LAUNCH_KEYS)
  if #extra > 0 then
    launch_bad(path, index, nil, "unknown keys: " .. table.concat(extra, ", "))
  end

  local name = entry.name
  if type(name) ~= "string" or name == "" then
    launch_bad(path, index, nil, "name must be a non-empty string")
  end
  if name:find("[\t\n%z]") then
    launch_bad(path, index, name, "name must not contain tab, newline, or NUL")
  end

  if not is_list(entry.argv) or #entry.argv == 0 then
    launch_bad(path, index, name, "argv must be a non-empty array of strings")
  end
  local argv = {}
  for j, part in ipairs(entry.argv) do
    if type(part) ~= "string" or part == "" then
      launch_bad(path, index, name, "argv[" .. tostring(j) .. "] must be a non-empty string")
    end
    if part:find("%z") then
      launch_bad(path, index, name, "argv[" .. tostring(j) .. "] must not contain NUL")
    end
    argv[j] = part
  end

  local cwd = parse_cwd(entry, path, index, name)

  local keep_open = false
  if entry.keep_open ~= nil then
    if type(entry.keep_open) ~= "boolean" then
      launch_bad(path, index, name, "keep_open must be a boolean")
    end
    keep_open = entry.keep_open
  end

  -- new_pane belonged to the fzf pane (reuse it, or open another float).
  -- The palette is the list now, so every launch is one float. Accept the
  -- boolean so version-1 files still load, and do not store it.
  if entry.new_pane ~= nil and type(entry.new_pane) ~= "boolean" then
    launch_bad(path, index, name, "new_pane must be a boolean")
  end

  local label = nil
  if entry.label ~= nil then
    if type(entry.label) ~= "string" then
      launch_bad(path, index, name, "label must be a string")
    end
    if entry.label ~= "" then
      label = entry.label
    end
  end

  local place = parse_place(entry, path, index, name)
  local bounds = parse_bounds(entry, path, index, name, place)
  local reuse = parse_reuse(entry, path, index, name)
  local key = parse_key(entry, path, index, name)
  local initial_input = parse_initial_input(entry, path, index, name)
  local prompt = parse_prompt(entry, path, index, name, argv, initial_input)

  return {
    name = name,
    argv = argv,
    cwd = cwd,
    keep_open = keep_open,
    label = label,
    place = place,
    bounds = bounds,
    reuse = reuse,
    key = key,
    prompt = prompt,
    initial_input = initial_input,
  }
end

local function load_launches(path)
  local file, err = io.open(path, "r")
  if file == nil then
    if type(err) == "string" and err:find("No such file", 1, true) then
      bad(path, "file not found")
    end
    bad(path, err or "cannot read file")
  end
  local text = file:read("*a")
  file:close()

  if type(rex) ~= "table" or type(rex.json) ~= "table" or type(rex.json.decode) ~= "function" then
    fail("rex.json.decode is unavailable")
  end
  local ok, decoded = pcall(rex.json.decode, text)
  if not ok then
    bad(path, "invalid JSON: " .. tostring(decoded))
  end
  if not is_object(decoded) then
    bad(path, "root must be an object")
  end
  local extra = unknown_key_list(decoded, ROOT_KEYS)
  if #extra > 0 then
    bad(path, "unknown keys: " .. table.concat(extra, ", "))
  end
  if decoded.version ~= 1 then
    bad(path, "version must be 1")
  end
  if not is_list(decoded.launches) then
    bad(path, "launches must be an array")
  end

  local launches = {}
  local seen = {}
  local seen_keys = {}
  for index, entry in ipairs(decoded.launches) do
    local launch = parse_launch(entry, path, index)
    if seen[launch.name] then
      bad(path, "duplicate launch name: " .. launch.name)
    end
    seen[launch.name] = true
    if launch.key ~= nil then
      if seen_keys[launch.key] then
        bad(path, "duplicate key: " .. launch.key)
      end
      seen_keys[launch.key] = true
    end
    launches[#launches + 1] = launch
  end
  return launches
end

local function pick_items(launches)
  local items = {}
  for _, launch in ipairs(launches) do
    local item = {
      id = launch.name,
      title = launch.name,
      icon = ICON,
    }
    if launch.label ~= nil then
      item.subtitle = launch.label
    end
    items[#items + 1] = item
  end
  return items
end

local function find_launch(launches, name)
  for _, launch in ipairs(launches) do
    if launch.name == name then
      return launch
    end
  end
  return nil
end

local function absolute_path_from_file_url(pwd)
  if type(pwd) ~= "string" or pwd == "" then
    return nil
  end
  local dir = pwd
  if dir:sub(1, 7) == "file://" then
    dir = dir:sub(8)
    if dir:sub(1, 1) ~= "/" then
      local slash = dir:find("/", 1, true)
      if slash == nil then
        return nil
      end
      dir = dir:sub(slash)
    end
  end
  if dir:sub(1, 1) ~= "/" then
    return nil
  end
  return dir
end

local function focused_directory(block_id)
  if type(block_id) ~= "string" or block_id == "" then
    return nil
  end
  if type(rex.block) ~= "table" or type(rex.block.call) ~= "function" then
    return nil
  end
  -- Prefer the foreground process cwd when Rex exposes it, then the
  -- terminal pwd. Both may arrive as file:// URLs.
  local info = rex.block.call("com.superlogical.terminal", "process", {
    block_id = block_id,
  })
  if type(info) == "table" then
    local fg = info.foreground or {}
    local child = info.child or {}
    local cwd = fg.cwd or child.cwd
    if type(cwd) == "string" and cwd ~= "" then
      local stripped = absolute_path_from_file_url(cwd)
      if stripped ~= nil then
        return stripped
      end
      if cwd:sub(1, 1) == "/" then
        return cwd
      end
    end
  end
  info = rex.block.call("com.superlogical.terminal", "pwd", {
    block_id = block_id,
  })
  if type(info) ~= "table" then
    return nil
  end
  return absolute_path_from_file_url(info.pwd)
end

local function substitute_string(text, prompts, answers)
  local result = text
  for _, prompt in ipairs(prompts) do
    local token = "{{" .. prompt.id .. "}}"
    local answer = answers[prompt.id] or ""
    local from = 1
    local parts = {}
    while true do
      local at = result:find(token, from, true)
      if at == nil then
        parts[#parts + 1] = result:sub(from)
        break
      end
      parts[#parts + 1] = result:sub(from, at - 1)
      parts[#parts + 1] = answer
      from = at + #token
    end
    result = table.concat(parts)
  end
  return result
end

local function ui_input()
  local ok, ui = pcall(function()
    return rex.ui
  end)
  if not ok or type(ui) ~= "table" or type(ui.input) ~= "function" then
    return nil
  end
  return ui.input
end

local function ask_prompts(prompts)
  local input = ui_input()
  if input == nil then
    fail("custom UI is unavailable (rex.ui.input). Update the Rex app")
  end
  local answers = {}
  for _, prompt in ipairs(prompts) do
    local request = { title = prompt.title }
    if prompt.placeholder ~= nil then
      request.placeholder = prompt.placeholder
    end
    if prompt.default ~= nil then
      request.value = prompt.default
    end
    local value, why, detail = input(request)
    if value == nil then
      if why == "cancelled" then
        return nil
      end
      local message = "input " .. tostring(why)
      if type(detail) == "string" and detail ~= "" then
        message = message .. ": " .. detail
      end
      fail(message)
    end
    if type(value) ~= "string" then
      fail("input returned an unexpected result")
    end
    if value == "" and prompt.required then
      fail("prompt " .. prompt.id .. " is required")
    end
    if value == "" then
      value = ""
    end
    answers[prompt.id] = value
  end
  return answers
end

local function session_view(session_id)
  if type(rex.session) ~= "table" or type(rex.session.view) ~= "function" then
    return nil, "cannot list panes"
  end
  local view, err
  if type(session_id) == "string" and session_id ~= "" then
    view, err = rex.session.view({ session_id = session_id })
  else
    view, err = rex.session.view({})
  end
  if view == nil then
    local message = "cannot list panes"
    if type(err) == "string" and err ~= "" then
      message = message .. ": " .. err
    end
    return nil, message
  end
  return view, nil
end

local function block_eligible(block, launch_name)
  if type(block) ~= "table" then
    return false
  end
  if block.label ~= launch_name then
    return false
  end
  local flavor = block.flavor
  if flavor == nil then
    return true
  end
  return flavor == TERMINAL_SHELL
end

local function find_reuse_panes(session_id, launch_name)
  local view, err = session_view(session_id)
  if view == nil then
    return nil, err
  end
  local hits = {}
  local windows = view.windows
  if type(windows) ~= "table" then
    return hits
  end
  for _, window in ipairs(windows) do
    if type(window) ~= "table" then
      goto continue_window
    end
    local layers = window.layers
    if type(layers) ~= "table" then
      goto continue_window
    end
    for _, layer in ipairs(layers) do
      if type(layer) ~= "table" then
        goto continue_layer
      end
      local blocks = layer.blocks
      if type(blocks) ~= "table" then
        goto continue_layer
      end
      for _, block in ipairs(blocks) do
        if block_eligible(block, launch_name) then
          hits[#hits + 1] = {
            block_id = block.block_id,
            layer_id = layer.layer_id,
            kind = layer.kind,
          }
        end
      end
      ::continue_layer::
    end
    ::continue_window::
  end
  return hits, nil
end

local function focus_reuse(hit)
  if type(hit.layer_id) == "string" and hit.layer_id ~= "" and hit.kind ~= "tiled" then
    if type(rex.session.raise_layer) == "function" then
      local _, raise_err = rex.session.raise_layer({ layer_id = hit.layer_id })
      if raise_err ~= nil and type(rex.log) == "function" then
        rex.log("warn", "rex_quicklaunch: could not raise layer " .. hit.layer_id .. ": " .. tostring(raise_err))
      end
    end
  end
  if type(hit.block_id) ~= "string" or hit.block_id == "" then
    fail("could not focus reused pane")
  end
  if type(rex.session.focus_block) ~= "function" then
    fail("could not focus reused pane")
  end
  local _, focus_err = rex.session.focus_block({ block_id = hit.block_id })
  if focus_err ~= nil then
    fail("could not focus reused pane: " .. tostring(focus_err))
  end
end

local function resolve_command(argv, launch_name, cwd, dirs)
  local exe = argv[1]
  local resolved = exe
  if exe:find("/", 1, true) then
    if exe:sub(1, 1) ~= "/" then
      local relative = exe
      if relative:sub(1, 2) == "./" then
        relative = relative:sub(3)
      end
      if cwd:sub(-1) == "/" then
        resolved = cwd .. relative
      else
        resolved = cwd .. "/" .. relative
      end
    end
  else
    resolved = nil
    for _, dir in ipairs(dirs) do
      local candidate = dir .. "/" .. exe
      if is_executable(candidate) then
        resolved = candidate
        break
      end
    end
    if resolved == nil then
      fail("command not found: " .. exe .. " (launch " .. launch_name .. ")")
    end
  end
  if not is_executable(resolved) then
    fail("command not found: " .. exe .. " (launch " .. launch_name .. ")")
  end

  local resolved_argv = {}
  for i, part in ipairs(argv) do
    resolved_argv[i] = part
  end
  resolved_argv[1] = resolved
  return resolved_argv
end

local function resolve_cwd(launch, block_id)
  local cwd
  local policy = launch.cwd.policy
  if policy == "focused" then
    cwd = focused_directory(block_id)
    if cwd == nil then
      fail(launch.name .. " uses cwd policy focused, but there is no focused directory")
    end
  elseif policy == "fixed" then
    cwd = launch.cwd.path
  else
    cwd = home_dir()
    if cwd == "" then
      fail(launch.name .. " uses cwd policy home, but HOME is not set")
    end
  end
  if not is_dir(cwd) then
    fail("working directory does not exist: " .. cwd)
  end
  return cwd
end

local function picker()
  local ok, ui = pcall(function()
    return rex.ui
  end)
  if not ok or type(ui) ~= "table" or type(ui.pick) ~= "function" then
    return nil
  end
  return ui.pick
end

local DEFERRED_FOCUS_DELAY = 0.15

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function rex_cli_path()
  for _, dir in ipairs(search_dirs()) do
    local candidate = dir .. "/rex"
    if is_executable(candidate) then
      return candidate
    end
  end
  return nil
end

local function schedule_reclaim_float_focus(session_id, layer_id)
  if type(session_id) ~= "string" or session_id == "" then
    return
  end
  if type(layer_id) ~= "string" or layer_id == "" then
    return
  end
  local exec = type(rex) == "table" and rex.exec or nil
  if type(exec) ~= "function" and type(exec) ~= "table" then
    return
  end
  if type(rex.json) ~= "table" or type(rex.json.encode) ~= "function" then
    return
  end
  local cli = rex_cli_path()
  if cli == nil then
    if type(rex.log) == "function" then
      rex.log("warn", "rex_quicklaunch: rex CLI not found; cannot schedule float focus")
    end
    return
  end
  local payload = rex.json.encode({
    session_id = session_id,
    layer_id = layer_id,
    state = "normal",
    focus = true,
  })
  local cmd = string.format(
    "(sleep %.2f; %s api call -s %s session.set_layer_state %s) >/dev/null 2>&1 &",
    DEFERRED_FOCUS_DELAY,
    shell_quote(cli),
    shell_quote(session_id),
    shell_quote(payload)
  )
  local _, err = exec({ "/bin/sh", "-c", cmd })
  if err ~= nil and type(rex.log) == "function" then
    rex.log("warn", "rex_quicklaunch: could not schedule float focus: " .. tostring(err))
  end
end

local function choose(launches, args, block_id)
  if args.name ~= nil then
    if type(args.name) ~= "string" or args.name == "" then
      fail("name must be a non-empty string")
    end
    return args.name
  end
  local pick = picker()
  if pick == nil then
    fail("custom UI is unavailable (rex.ui.pick). Update the Rex app")
  end
  local placeholder = "Filter launches"
  local cwd_note = focused_directory(block_id)
  if cwd_note ~= nil then
    placeholder = placeholder .. "  ·  " .. cwd_note
  end
  local id, why, detail = pick({
    title = "Quick Launch",
    placeholder = placeholder,
    items = pick_items(launches),
  })
  if id == nil then
    if why == "cancelled" then
      return nil
    end
    local message = "picker " .. tostring(why)
    if type(detail) == "string" and detail ~= "" then
      message = message .. ": " .. detail
    end
    fail(message)
  end
  if type(id) ~= "string" then
    fail("picker returned an unexpected result")
  end
  return id
end

local function build_layout(launch, argv, cwd, dirs, initial_input)
  local options = {
    command = argv,
    cwd = cwd,
    shell = "none",
    exit = { on_completion = not launch.keep_open },
    path_prepend = dirs,
  }
  if initial_input ~= nil then
    options.initial_input = initial_input
  end
  return rex.layout.block({
    flavor = TERMINAL_SHELL,
    label = launch.name,
    options = options,
  })
end

function M.open(ctx, args)
  if type(ctx) ~= "table" or type(ctx.session_id) ~= "string" or ctx.session_id == "" then
    fail("run this from a Rex session (a key or the command palette)")
  end
  args = args or {}
  local used_palette = args.name == nil
  local path = config_path()
  local launches = load_launches(path)
  if #launches == 0 then
    bad(path, "no launches")
  end

  local name = choose(launches, args, ctx.block_id)
  if name == nil then
    return nil
  end
  local launch = find_launch(launches, name)
  if launch == nil then
    fail("no launch named " .. name)
  end

  if launch.reuse then
    local hits, view_err = find_reuse_panes(ctx.session_id, launch.name)
    if view_err ~= nil then
      fail(view_err)
    end
    if #hits > 1 then
      fail("more than one pane named " .. launch.name)
    end
    if #hits == 1 then
      focus_reuse(hits[1])
      if used_palette and hits[1].kind ~= "tiled" then
        schedule_reclaim_float_focus(ctx.session_id, hits[1].layer_id)
      end
      return {
        layer_id = hits[1].layer_id,
        block_id = hits[1].block_id,
        name = launch.name,
        reused = true,
      }
    end
  end

  if launch.place ~= "float" then
    if type(ctx.block_id) ~= "string" or ctx.block_id == "" then
      fail("split placement needs a focused block")
    end
  end

  local answers
  if #launch.prompt > 0 then
    answers = ask_prompts(launch.prompt)
    if answers == nil then
      return nil
    end
  else
    answers = {}
  end

  local argv = {}
  for i, part in ipairs(launch.argv) do
    local substituted = substitute_string(part, launch.prompt, answers)
    if substituted:find("%z") then
      fail("substituted argv must not contain NUL")
    end
    argv[i] = substituted
  end

  local initial_input = nil
  if launch.initial_input ~= nil then
    initial_input = substitute_string(launch.initial_input, launch.prompt, answers)
    if initial_input:find("%z") then
      fail("substituted initial_input must not contain NUL")
    end
    if initial_input == "" then
      initial_input = nil
    end
  end

  local cwd = resolve_cwd(launch, ctx.block_id)
  local dirs = search_dirs()
  argv = resolve_command(argv, launch.name, cwd, dirs)
  local layout = build_layout(launch, argv, cwd, dirs, initial_input)

  local layer
  local err
  if launch.place == "float" then
    layer, err = rex.session.new_layer({
      bounds = launch.bounds,
      focus = true,
      layout = layout,
    })
  else
    local split = PLACE_SPLIT[launch.place]
    layer, err = rex.session.new_split({
      direction = split.direction,
      side = split.side,
      anchor_id = ctx.block_id,
      focus = true,
      layout = layout,
    })
  end
  if layer == nil then
    fail("could not open a terminal: " .. tostring(err))
  end
  local block_id = nil
  if type(layer.block_ids) == "table" then
    block_id = layer.block_ids[1]
  end
  if type(block_id) == "string" and block_id ~= "" and type(rex.session.focus_block) == "function" then
    local _, focus_err = rex.session.focus_block({ block_id = block_id })
    if focus_err ~= nil and type(rex.log) == "function" then
      rex.log("warn", "rex_quicklaunch: could not focus " .. block_id .. ": " .. tostring(focus_err))
    end
  end
  if used_palette and launch.place == "float" then
    schedule_reclaim_float_focus(ctx.session_id, layer.layer_id)
  end
  return {
    layer_id = layer.layer_id,
    block_id = block_id,
    name = launch.name,
    reused = false,
  }
end

local function register_key_binds()
  if type(rex.bind) ~= "function" then
    return
  end
  local ok, launches_or_err = pcall(function()
    return load_launches(config_path())
  end)
  if not ok then
    if type(rex.log) == "function" then
      rex.log("warn", "rex_quicklaunch: skipped key bindings")
    end
    return
  end
  for _, launch in ipairs(launches_or_err) do
    if launch.key ~= nil then
      local bind_ok, bind_err = pcall(rex.bind, launch.key, "rex_quicklaunch", { name = launch.name })
      if not bind_ok and type(rex.log) == "function" then
        rex.log("warn", "rex_quicklaunch: could not bind " .. launch.key .. ": " .. tostring(bind_err))
      end
    end
  end
end

if type(rex) == "table" and type(rex.action) == "function" then
  rex.action({
    name = "rex_quicklaunch",
    title = "Quick Launch…",
    description = "Pick a configured command and run it in a floating or split terminal.",
    keywords = "quicklaunch command run launch",
    args = { name = "string?" },
    run = function(ctx, args)
      return M.open(ctx, args)
    end,
  })
  register_key_binds()
end

return M
