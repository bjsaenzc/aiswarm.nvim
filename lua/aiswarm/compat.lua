-- Legacy `hive` surface: Lua API, option translation, command aliases and event names (SDD-009/012/014).
local M = {}
local config = require("aiswarm.config")

local function A() return require("aiswarm") end

--- The table returned by require("hive"). Same functions as hive.nvim 2.x, one implementation.
function M.hive_api()
  if M._api then return M._api end
  local api = setmetatable({}, { __index = function(_, k) return A()[k] end })
  function api.setup(opts)
    config.warn_legacy("require.hive", 'require("hive").setup is deprecated; use require("aiswarm").setup')
    return A().setup(opts)
  end
  function api.open()       return A().open() end
  function api.pick()       return A().pick() end
  function api.results()    return A().results() end
  function api.add(prefill) return A().new(prefill) end
  function api.tail(id)     return A().tail(id) end
  function api.peek(id)     return A().peek(id) end
  function api.go(id)       return A().attach(id) end
  function api.kill(id)     return A().kill(id) end
  function api.toggle_pause() return A().toggle_pause() end
  function api.statusline() return A().statusline() end
  function api.on_event(e)  return A().on_event(e) end
  function api.on_event_json(s, root) return A().on_event_json(s, root) end
  function api.refresh(cb)  return A().refresh(cb) end
  function api.root()       return A().root() end
  function api.run(args, cb) return A().run(args, cb) end
  function api.run_sync(args, ms) return A().run_sync(args, ms) end
  function api.env()        return A().env() end
  function api.cmd(args)    return A().cmd(args) end
  M._api = api
  return api
end

--- The ten legacy commands, routed to the canonical implementation.
M.legacy_commands = {
  { "Hive",        "open",     nargs = 0 },
  { "HivePick",    "pick",     nargs = 0 },
  { "HiveResults", "results",  nargs = 0 },
  { "HiveRefresh", "refresh",  nargs = 0 },
  { "HivePause",   "pause",    nargs = 0 },
  { "HiveTail",    "tail",     nargs = "?" },
  { "HivePeek",    "peek",     nargs = "?" },
  { "HiveGo",      "attach",   nargs = "?" },
  { "HiveKill",    "kill",     nargs = "?" },
  { "HiveAdd",     "new",      nargs = 0, range = true },
}

function M.register_legacy_commands()
  local commands = require("aiswarm.commands")
  for _, c in ipairs(M.legacy_commands) do
    local name, sub = c[1], c[2]
    vim.api.nvim_create_user_command(name, function(a)
      commands.dispatch(sub, a.args ~= "" and { a.args } or {}, a)
    end, { nargs = c.nargs, range = c.range, complete = c.nargs ~= 0 and commands.complete_ids or nil,
      desc = "Legacy alias of :AISwarm " .. sub })
  end
end

--- Emit legacy HiveEvent for a normalized event when enabled.
function M.emit_hive_event(e)
  if not A().config.compat.hive_events then return end
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "HiveEvent", data = e })
  if not ok then A().err("HiveEvent callback failed: " .. tostring(err)) end
end

return M
