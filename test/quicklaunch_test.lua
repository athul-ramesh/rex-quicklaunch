local function sh_quote(text)
  local escaped = tostring(text):gsub("'", "'\\''")
  return "'" .. escaped .. "'"
end

local function run(cmd)
  local ok = os.execute(cmd)
  if ok ~= true then
    error("command failed: " .. cmd, 0)
  end
end

local pipe = assert(io.popen("mktemp -d"))
local tmp = pipe:read("*l")
pipe:close()
if type(tmp) ~= "string" or tmp == "" then
  error("mktemp failed", 0)
end

local decoder = tmp .. "/json_to_lua.py"
do
  local file = assert(io.open(decoder, "w"))
  file:write([[
import json, sys

def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return str(int(v)) if v.is_integer() else repr(v)
    if isinstance(v, str):
        out = ['"']
        for ch in v:
            o = ord(ch)
            if ch == "\\":
                out.append("\\\\")
            elif ch == '"':
                out.append('\\"')
            elif ch == "\n":
                out.append("\\n")
            elif ch == "\r":
                out.append("\\r")
            elif ch == "\t":
                out.append("\\t")
            elif o < 32:
                out.append("\\%03d" % o)
            else:
                out.append(ch)
        out.append('"')
        return "".join(out)
    if isinstance(v, list):
        return "{" + ",".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = ["[" + lua(str(k)) + "]=" + lua(val) for k, val in v.items()]
        return "{" + ",".join(parts) + "}"
    sys.exit("bad type")

try:
    data = json.loads(sys.stdin.read())
except json.JSONDecodeError as e:
    sys.stderr.write(str(e))
    sys.exit(1)
sys.stdout.write("return " + lua(data))
]])
  file:close()
end

local function decode_json(text)
  local input = tmp .. "/decode-in.json"
  local output = tmp .. "/decode-out.lua"
  local errpath = tmp .. "/decode-err.txt"
  local file = assert(io.open(input, "w"))
  file:write(text)
  file:close()
  local cmd = "python3 " .. sh_quote(decoder)
    .. " < " .. sh_quote(input)
    .. " > " .. sh_quote(output)
    .. " 2> " .. sh_quote(errpath)
  if os.execute(cmd) ~= true then
    local errfile = io.open(errpath, "r")
    local message = "invalid JSON"
    if errfile ~= nil then
      message = errfile:read("*a") or message
      errfile:close()
    end
    error(message)
  end
  local out = assert(io.open(output, "r"))
  local source = out:read("*a")
  out:close()
  local chunk, err = load(source)
  if chunk == nil then
    error(err)
  end
  return chunk()
end

local script = arg[0]
if script:sub(1, 1) ~= "/" then
  local pwd_pipe = assert(io.popen("pwd"))
  local cwd = pwd_pipe:read("*l")
  pwd_pipe:close()
  script = cwd .. "/" .. script
end
local root = script:match("^(.*)/test/quicklaunch_test%.lua$")
if root == nil then
  error("cannot find repo root from " .. script, 0)
end

local real_getenv = os.getenv
local real_home = real_getenv("HOME")
local env = {}
os.getenv = function(name)
  if env[name] ~= nil then
    return env[name]
  end
  return real_getenv(name)
end

local calls = { layers = {}, picks = {} }
local action

rex = {
  json = { decode = decode_json },
  action = function(spec)
    action = spec
  end,
  exec = setmetatable({}, {
    __call = function(_, argv)
      if argv[1] ~= "/bin/test" then
        return nil, "unexpected command"
      end
      local cmd = "/bin/test " .. argv[2] .. " " .. sh_quote(argv[3]) .. " && printf yes"
      local probe = io.popen(cmd)
      if probe == nil then
        return nil, "cannot run /bin/test"
      end
      local out = probe:read("*a")
      probe:close()
      local yes = out == "yes"
      return { ok = yes, code = yes and 0 or 1, stdout = "", stderr = "" }
    end,
  }),
  session = {
    new_layer = function(request)
      calls.layers[#calls.layers + 1] = request
      return { layer_id = "layer-1" }
    end,
  },
  layout = {
    block = function(spec)
      return spec
    end,
  },
}

local M = dofile(root .. "/lua/rex_quicklaunch.lua")

local failures = 0
local function check(cond, message)
  if cond then
    return
  end
  failures = failures + 1
  io.stderr:write("FAIL: " .. message .. "\n")
end

local ctx = { session_id = "sess-1", block_id = "block-1" }

local function begin(pick_fn)
  env.REX_QUICKLAUNCH_CONFIG = nil
  env.HOME = nil
  env.PATH = nil
  calls.layers = {}
  calls.picks = {}
  calls.pwd = { pwd = "file:///tmp" }
  rex.ui = {
    pick = function(spec)
      calls.picks[#calls.picks + 1] = spec
      if pick_fn == nil then
        return nil, "cancelled"
      end
      return pick_fn(spec)
    end,
  }
  rex.block = {
    call = function(_, _, args)
      calls.block_args = args
      return calls.pwd
    end,
  }
end

local config_n = 0
local function write_config(text)
  config_n = config_n + 1
  local path = tmp .. "/cfg-" .. tostring(config_n) .. ".json"
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
  env.REX_QUICKLAUNCH_CONFIG = path
  return path
end

local function expect_error(call_ctx, args, needle)
  local ok, result = pcall(M.open, call_ctx, args)
  if ok then
    check(false, "expected error containing '" .. needle .. "', call succeeded")
    return
  end
  local found = type(result) == "string" and result:find(needle, 1, true) ~= nil
  check(found, "expected '" .. needle .. "' in: " .. tostring(result))
end

local function opened(call_ctx, args)
  local ok, result = pcall(M.open, call_ctx, args)
  if not ok then
    check(false, "open failed: " .. tostring(result))
    return nil
  end
  if #calls.layers ~= 1 then
    check(false, "expected one float, got " .. tostring(#calls.layers))
    return nil
  end
  local layer = calls.layers[1]
  check(layer.focus == true, "float is focused")
  check(type(layer.bounds) == "table", "float has bounds")
  check(layer.layout ~= nil, "float has a layout")
  if layer.layout == nil then
    return nil
  end
  check(layer.layout.flavor == "com.superlogical.terminal.shell", "terminal flavor")
  return layer.layout, result
end

local function contains(list, value)
  if type(list) ~= "table" then
    return false
  end
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

local function echo_json(extra)
  return [[
{
  "version": 1,
  "launches": [
    {
      "name": "echo",
      "argv": ["/bin/echo", "hello"],
      "cwd": { "policy": "fixed", "path": "/tmp" }
      ]] .. (extra or "") .. [[
    }
  ]
}
]]
end

begin()
env.REX_QUICKLAUNCH_CONFIG = root .. "/quicklaunch.example.json"
do
  local ok, result = pcall(M.open, ctx, nil)
  check(ok and result == nil, "cancelling the example picker returns nil, got " .. tostring(result))
  check(#calls.layers == 0, "cancel opens no float")
  check(#calls.picks == 1, "cancel still shows the palette")
  local items = calls.picks[1] and calls.picks[1].items or {}
  check(#items == 4, "example shows 4 launches, got " .. tostring(#items))
  check(calls.picks[1].title == "Quick Launch", "palette title")
  local lazygit = items[1]
  check(lazygit ~= nil and lazygit.id == "lazygit" and lazygit.title == "lazygit", "lazygit id and title")
  check(lazygit ~= nil and lazygit.subtitle == "git UI", "lazygit subtitle is the label")
  check(lazygit ~= nil and lazygit.icon == "terminal", "lazygit icon")
  check(items[2] ~= nil and items[2].id == "build" and items[2].subtitle == nil, "build has no subtitle")
  check(items[3] ~= nil and items[3].id == "htop" and items[3].icon == "terminal", "htop row")
  check(items[4] ~= nil and items[4].id == "agent-demo", "agent-demo row")
end

begin(function()
  return "echo"
end)
write_config(echo_json())
do
  local layout = opened(ctx, nil)
  if layout ~= nil then
    local options = layout.options
    check(layout.label == "echo", "float label is the launch name")
    check(options.shell == "none", "shell is none")
    check(options.cwd == "/tmp", "fixed cwd")
    check(options.command[1] == "/bin/echo", "absolute command is unchanged")
    check(options.command[2] == "hello", "argv tail is preserved")
    check(options.exit.on_completion == true, "keep_open defaults to close on exit")
    check(contains(options.path_prepend, "/opt/homebrew/bin"), "path_prepend includes Homebrew")
    check(contains(options.path_prepend, "/usr/bin"), "path_prepend includes /usr/bin")
    check(contains(options.path_prepend, "/bin"), "path_prepend includes /bin")
    if type(real_home) == "string" and real_home ~= "" then
      check(contains(options.path_prepend, real_home .. "/.local/bin"), "path_prepend includes ~/.local/bin")
    end
    check(#calls.picks == 1, "palette was shown")
  end
end

begin()
write_config(echo_json(',\n      "keep_open": true'))
do
  local layout = opened(ctx, { name = "echo" })
  if layout ~= nil then
    check(layout.options.exit.on_completion == false, "keep_open leaves the float open")
    check(#calls.picks == 0, "name= skips the palette")
  end
end

begin()
write_config([[
{
  "version": 1,
  "launches": [
    {
      "name": "echo",
      "argv": ["/bin/echo", "hello"],
      "cwd": { "policy": "focused" },
      "new_pane": true,
      "keep_open": false
    }
  ]
}
]])
calls.pwd = { pwd = "file://Mac-mini.local/tmp" }
do
  local layout = opened(ctx, { name = "echo" })
  if layout ~= nil then
    check(layout.options.cwd == "/tmp", "focused cwd strips a file://host URL, got " .. tostring(layout.options.cwd))
    check(layout.options.exit.on_completion == true, "new_pane true still closes when keep_open is false")
    check(#calls.layers == 1, "new_pane still opens one float")
  end
end

begin()
write_config([[
{
  "version": 1,
  "launches": [
    {
      "name": "echo",
      "argv": ["/bin/echo"],
      "cwd": { "policy": "home" },
      "new_pane": false,
      "keep_open": true
    }
  ]
}
]])
do
  local layout = opened({ session_id = "sess-1" }, { name = "echo" })
  if layout ~= nil then
    check(layout.options.cwd == real_home, "home cwd, got " .. tostring(layout.options.cwd))
    check(layout.options.exit.on_completion == false, "new_pane false still honors keep_open")
  end
end

local home = tmp .. "/home"
local work = home .. "/work"
run("mkdir -p " .. sh_quote(work))
begin()
env.HOME = home
write_config([[
{
  "version": 1,
  "launches": [
    {
      "name": "echo",
      "argv": ["/bin/echo"],
      "cwd": { "policy": "fixed", "path": "~/work" }
    }
  ]
}
]])
do
  local layout = opened(ctx, { name = "echo" })
  if layout ~= nil then
    check(layout.options.cwd == work, "tilde cwd expands, got " .. tostring(layout.options.cwd))
  end
end

local bin = tmp .. "/bin"
local tool = bin .. "/mytool"
run("mkdir -p " .. sh_quote(bin))
do
  local file = assert(io.open(tool, "w"))
  file:write("#!/bin/sh\n")
  file:close()
end
run("chmod +x " .. sh_quote(tool))

begin()
env.PATH = bin
write_config([[
{
  "version": 1,
  "launches": [
    {
      "name": "mine",
      "argv": ["mytool", "--flag"],
      "cwd": { "policy": "fixed", "path": "/tmp" }
    }
  ]
}
]])
do
  local layout = opened(ctx, { name = "mine" })
  if layout ~= nil then
    check(layout.options.command[1] == tool, "PATH lookup, got " .. tostring(layout.options.command[1]))
    check(layout.options.command[2] == "--flag", "PATH lookup keeps the argv tail")
    check(layout.options.path_prepend[1] == bin, "path_prepend starts with PATH")
    check(contains(layout.options.path_prepend, "/bin"), "fallbacks follow PATH")
  end
end

local rel_dir = tmp .. "/rel"
local rel_tool = rel_dir .. "/tool"
run("mkdir -p " .. sh_quote(rel_dir))
do
  local file = assert(io.open(rel_tool, "w"))
  file:write("#!/bin/sh\n")
  file:close()
end
run("chmod +x " .. sh_quote(rel_tool))

begin()
env.PATH = bin
write_config(string.format([[
{
  "version": 1,
  "launches": [
    {
      "name": "rel",
      "argv": ["./tool"],
      "cwd": { "policy": "fixed", "path": %q }
    }
  ]
}
]], rel_dir))
do
  local layout = opened(ctx, { name = "rel" })
  if layout ~= nil then
    check(layout.options.command[1] == rel_tool, "relative argv resolves under cwd, got " .. tostring(layout.options.command[1]))
  end
end

begin()
env.PATH = bin
write_config(string.format([[
{
  "version": 1,
  "launches": [
    {
      "name": "bare",
      "argv": ["tool"],
      "cwd": { "policy": "fixed", "path": %q }
    }
  ]
}
]], rel_dir))
expect_error(ctx, { name = "bare" }, "command not found: tool")
check(#calls.layers == 0, "missing command opens no float")

begin()
write_config([[
{
  "version": 1,
  "launches": [
    {
      "name": "gone",
      "argv": ["/bin/echo"],
      "cwd": { "policy": "fixed", "path": "/tmp/rex-quicklaunch-missing-dir" }
    }
  ]
}
]])
expect_error(ctx, { name = "gone" }, "working directory does not exist: /tmp/rex-quicklaunch-missing-dir")

begin()
write_config([[
{
  "version": 1,
  "launches": [
    {
      "name": "here",
      "argv": ["/bin/echo"],
      "cwd": { "policy": "focused" }
    }
  ]
}
]])
expect_error({ session_id = "sess-1" }, { name = "here" }, "no focused directory")

begin()
calls.pwd = nil
write_config([[
{
  "version": 1,
  "launches": [
    {
      "name": "here",
      "argv": ["/bin/echo"],
      "cwd": { "policy": "focused" }
    }
  ]
}
]])
expect_error(ctx, { name = "here" }, "no focused directory")

local missing = tmp .. "/missing.json"
begin()
env.REX_QUICKLAUNCH_CONFIG = missing
expect_error(ctx, nil, "file not found")
expect_error(ctx, nil, missing)
check(#calls.picks == 0, "bad config does not open the palette")

begin()
write_config("{")
expect_error(ctx, nil, "invalid JSON")

begin()
write_config('{ "version": 2, "launches": [] }')
expect_error(ctx, nil, "version must be 1")

begin()
write_config('{ "version": 1, "launches": [] }')
expect_error(ctx, nil, "no launches")

begin()
write_config([[
{
  "version": 1,
  "launches": [
    { "name": "a", "argv": ["/bin/echo"], "cwd": { "policy": "home" } },
    { "name": "a", "argv": ["/bin/echo"], "cwd": { "policy": "home" } }
  ]
}
]])
expect_error(ctx, nil, "duplicate launch name: a")

begin()
write_config([[
{
  "version": 1,
  "extra": true,
  "launches": []
}
]])
expect_error(ctx, nil, "unknown keys: extra")

begin()
write_config([[
{
  "version": 1,
  "launches": [
    {
      "name": "a",
      "argv": ["/bin/echo"],
      "cwd": { "policy": "focused", "path": "/tmp" }
    }
  ]
}
]])
expect_error(ctx, nil, "cwd.path is not allowed")

begin()
rex.ui = nil
write_config(echo_json())
expect_error(ctx, nil, "custom UI is unavailable")

begin()
rex.ui = nil
write_config(echo_json())
do
  local layout = opened(ctx, { name = "echo" })
  check(layout ~= nil, "name= runs without custom UI")
end

begin(function()
  return nil, "unsupported"
end)
write_config(echo_json())
expect_error(ctx, nil, "picker unsupported")
check(#calls.layers == 0, "unsupported picker opens no float")

begin(function()
  return nil, "failed", "palette broke"
end)
write_config(echo_json())
expect_error(ctx, nil, "picker failed: palette broke")

begin()
write_config(echo_json())
expect_error({}, nil, "Rex session")
check(#calls.picks == 0, "no session does not open the palette")

begin()
write_config(echo_json())
expect_error(ctx, { name = "nope" }, "no launch named nope")

check(action ~= nil, "action is registered")
if action ~= nil then
  check(action.name == "rex_quicklaunch", "action name")
  check(action.title == "Quick Launch…", "action title")
  check(type(action.keywords) == "string" and action.keywords:find("fzf", 1, true) == nil, "keywords do not mention fzf")
  check(type(action.description) == "string" and action.description:find("floating terminal", 1, true) ~= nil, "description names the float")
  check(action.args ~= nil and action.args.name == "string?", "name argument is optional")
  begin()
  write_config(echo_json())
  local ok, result = pcall(action.run, ctx, { name = "echo" })
  check(ok and type(result) == "table" and result.name == "echo", "registered action launches, got " .. tostring(result))
end

run("rm -rf " .. sh_quote(tmp))

if failures > 0 then
  io.stderr:write(tostring(failures) .. " failed\n")
  os.exit(1)
end
print("ok")
