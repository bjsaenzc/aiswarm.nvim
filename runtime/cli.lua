-- aiswarm v3 command runtime. Started by bin/aiswarm as
--   nvim --clean --headless --noplugin -u NONE -i NONE -n -l runtime/cli.lua <command> [args]
-- Loads only bundled modules. Exit codes: 0 ok | 1 generic | 2 not found | 3 conflict | 4 environment.
local plugin = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path
vim.opt.runtimepath:prepend(plugin)
_G.AISWARM_PLUGIN_ROOT = plugin

local U = require("aiswarm.runtime.util")
local commands = require("aiswarm.runtime.commands")

local argv = _G.arg or {}
local name = table.remove(argv, 1) or "help"
local json = false
for i = #argv, 1, -1 do if argv[i] == "--json" then json = true; table.remove(argv, i) end end

local function out(s) io.stdout:write(s); io.stdout:flush() end
local function die(code, msg)
  if json then io.stderr:write(vim.json.encode({ error = msg, code = code }) .. "\n")
  else io.stderr:write("aiswarm: " .. tostring(msg) .. "\n") end
  io.stderr:flush()
  os.exit(code)
end

local cmd = commands.get(name)
if not cmd then die(1, "unknown command: " .. tostring(name) .. " (try `aiswarm help`)") end
local parsed, perr = U.parse_args(argv, cmd.bools)
if not parsed then die(1, perr) end
parsed.json = json
parsed.root = vim.env.AISWARM_ROOT or vim.env.HIVE_ROOT or (vim.uv.cwd() .. "/.aiswarm")
parsed.plugin = plugin

local ok, res = xpcall(function() return cmd.run(parsed) end, function(e)
  if type(e) == "table" and e.code then return e end
  return { code = 1, message = tostring(e), traceback = debug.traceback("", 2) }
end)
if not ok then
  if res.traceback and vim.env.AISWARM_DEBUG then io.stderr:write(res.traceback .. "\n") end
  die(res.code or 1, res.message)
end
if res ~= nil then
  if type(res) == "string" then out(res:sub(-1) == "\n" and res or (res .. "\n"))
  elseif json or cmd.always_json then out(vim.json.encode(res) .. "\n")
  elseif cmd.render then out(cmd.render(res))
  else out(vim.inspect(res) .. "\n") end
end
os.exit(0)
