local M = {}

local home = os.getenv("HOME") or ""
local PICKER_LABEL = "rex-quicklaunch"
local BOUNDS = { x = 0.25, y = 0.15, w = 0.5, h = 0.7 }
local SHELL_NONE = "none"
local TERMINAL_SHELL = "com.superlogical.terminal.shell"

local REX_SERVER_PATH_FALLBACKS = {
  "/opt/homebrew/bin",
  "/usr/local/bin",
  "/usr/bin",
  "/bin",
  home .. "/Library/Application Support/com.superlogical.rex"
    .. "/RexServer/Versions/Current/Rex Server.app/Contents/MacOS",
}

local function path_executable(p)
  local f = io.open(p, "rb")
  if f then
    f:close()
    return p
  end
  return nil
end

local function find_in_path(name)
  local seen = {}
  local function try(prefix)
    if seen[prefix] then return nil end
    seen[prefix] = true
    return path_executable(prefix .. "/" .. name)
  end
  for prefix in string.gmatch(os.getenv("PATH") or "", "[^:]+") do
    local hit = try(prefix)
    if hit then return hit end
  end
  for _, prefix in ipairs(REX_SERVER_PATH_FALLBACKS) do
    local hit = try(prefix)
    if hit then return hit end
  end
  return nil
end

local function absolute_path_from_file_url(pwd)
  if type(pwd) ~= "string" or pwd == "" then
    return ""
  end
  local dir = pwd
  if dir:sub(1, 7) == "file://" then
    dir = dir:sub(8)
    if dir:sub(1, 1) ~= "/" then
      local slash = dir:find("/", 1, true)
      if slash == nil then
        return ""
      end
      dir = dir:sub(slash)
    end
  end
  return dir
end

local function focused_cwd(block_id)
  if block_id == nil or block_id == "" then
    return ""
  end
  local info = rex.block.call("com.superlogical.terminal", "pwd", {
    block_id = block_id,
  })
  if info == nil then
    return ""
  end
  return absolute_path_from_file_url(info.pwd)
end

local function find_picker(view)
  for _, win in ipairs(view.windows or {}) do
    for _, layer in ipairs(win.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.label == PICKER_LABEL then
          return win.window_id, layer.layer_id, block.block_id
        end
      end
    end
  end
  return nil
end

local function helper_path()
  local override = os.getenv("REX_QUICKLAUNCH_HELPER")
  if override ~= nil and override ~= "" then
    return override
  end
  return home .. "/.config/rex/rex-quicklaunch"
end

function M.open(ctx)
  local view, err = rex.session.view{}
  if view == nil then
    error(err, 0)
  end

  local _, layer_id, block_id = find_picker(view)
  if block_id ~= nil then
    rex.session.raise_layer{ layer_id = layer_id }
    rex.session.focus_block{ block_id = block_id }
    return { focused_existing = true, block_id = block_id }
  end

  local python3 = find_in_path("python3")
  if python3 == nil then
    error("python3 not found (checked PATH and Homebrew fallbacks)", 0)
  end

  local argv = {
    python3,
    helper_path(),
    "--session", ctx.session_id,
    "--block", ctx.block_id or "",
    "--focused-cwd", focused_cwd(ctx.block_id),
  }
  local res, lerr = rex.session.new_layer{
    bounds = BOUNDS,
    focus = true,
    layout = rex.layout.block{
      flavor = TERMINAL_SHELL,
      label = PICKER_LABEL,
      options = {
        cwd = home,
        command = argv,
        shell = SHELL_NONE,
      },
    },
  }
  if res == nil then
    error(lerr, 0)
  end
  local new_block = nil
  if res.block_ids ~= nil and res.block_ids[1] ~= nil then
    new_block = res.block_ids[1]
  end
  return {
    focused_existing = false,
    layer_id = res.layer_id,
    block_id = new_block,
  }
end

rex.action{
  name = "rex_quicklaunch",
  title = "Quick Launch…",
  description = "Fuzzy-pick a configured command and run it in this floating pane.",
  keywords = "quicklaunch fzf command run",
  run = function(ctx, _args)
    if ctx.session_id == nil then
      error("run from a terminal pane (key or palette), not bare rex CLI", 0)
    end
    return M.open(ctx)
  end,
}

return M
