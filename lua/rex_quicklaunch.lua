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
}
local CWD_KEYS = { policy = true, path = true }

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

  return {
    name = name,
    argv = argv,
    cwd = cwd,
    keep_open = keep_open,
    label = label,
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
  for index, entry in ipairs(decoded.launches) do
    local launch = parse_launch(entry, path, index)
    if seen[launch.name] then
      bad(path, "duplicate launch name: " .. launch.name)
    end
    seen[launch.name] = true
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
  local info = rex.block.call("com.superlogical.terminal", "pwd", {
    block_id = block_id,
  })
  if type(info) ~= "table" then
    return nil
  end
  return absolute_path_from_file_url(info.pwd)
end

local function resolve_command(launch, cwd, dirs)
  local exe = launch.argv[1]
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
      fail("command not found: " .. exe .. " (launch " .. launch.name .. ")")
    end
  end
  if not is_executable(resolved) then
    fail("command not found: " .. exe .. " (launch " .. launch.name .. ")")
  end

  local argv = {}
  for i, part in ipairs(launch.argv) do
    argv[i] = part
  end
  argv[1] = resolved
  return argv
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

local function choose(launches, args)
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
  local id, why, detail = pick({
    title = "Quick Launch",
    placeholder = "Filter launches",
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

function M.open(ctx, args)
  if type(ctx) ~= "table" or type(ctx.session_id) ~= "string" or ctx.session_id == "" then
    fail("run this from a Rex session (a key or the command palette)")
  end
  args = args or {}
  local path = config_path()
  local launches = load_launches(path)
  if #launches == 0 then
    bad(path, "no launches")
  end

  local name = choose(launches, args)
  if name == nil then
    return nil
  end
  local launch = find_launch(launches, name)
  if launch == nil then
    fail("no launch named " .. name)
  end

  local cwd = resolve_cwd(launch, ctx.block_id)
  local dirs = search_dirs()
  local argv = resolve_command(launch, cwd, dirs)
  local layer, err = rex.session.new_layer({
    bounds = BOUNDS,
    focus = true,
    layout = rex.layout.block({
      flavor = TERMINAL_SHELL,
      label = launch.name,
      options = {
        command = argv,
        cwd = cwd,
        shell = "none",
        exit = { on_completion = not launch.keep_open },
        path_prepend = dirs,
      },
    }),
  })
  if layer == nil then
    fail("could not open a terminal: " .. tostring(err))
  end
  return {
    layer_id = layer.layer_id,
    name = launch.name,
  }
end

if type(rex) == "table" and type(rex.action) == "function" then
  rex.action({
    name = "rex_quicklaunch",
    title = "Quick Launch…",
    description = "Pick a configured command and run it in a floating terminal.",
    keywords = "quicklaunch command run launch",
    args = { name = "string?" },
    run = function(ctx, args)
      return M.open(ctx, args)
    end,
  })
end

return M
