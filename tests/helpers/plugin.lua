-- Fresh-load helpers for the editor modules.
local M = {}
local sb = require("helpers.sandbox")

--- Unload every aiswarm/hive module and command guard.
function M.unload()
  for name in pairs(package.loaded) do
    if name == "hive" or name:match("^hive%.") or name == "aiswarm" or name:match("^aiswarm%.") then package.loaded[name] = nil end
  end
  vim.g.loaded_hive, vim.g.loaded_aiswarm = nil, nil
  for _, name in ipairs({ "AISwarm", "Hive", "HivePick", "HiveResults", "HiveRefresh", "HivePause", "HiveTail", "HivePeek", "HiveGo", "HiveKill", "HiveAdd" }) do
    pcall(vim.api.nvim_del_user_command, name)
  end
end

--- Load and set up aiswarm against `root` (follow off by default, no server registration).
function M.setup(t, root, opts)
  M.unload()
  local A = require("aiswarm")
  A.setup(vim.tbl_deep_extend("force", { bin = sb.bin("aiswarm"), root = root, follow = false, register_server = false,
    dashboard = { refresh_ms = 60000 } }, opts or {}))
  t:defer(function() pcall(function() require("aiswarm.project").close() end) end)
  return A, A.state()
end

function M.source_plugin()
  vim.g.loaded_hive, vim.g.loaded_aiswarm = nil, nil
  vim.cmd.source(sb.plugin .. "/plugin/aiswarm.lua")
end

--- Wait for a fresh snapshot.
function M.refresh(t, A)
  local snap, err
  A.refresh(function(s, e) snap, err = s, e end)
  t:wait(5000, function() return snap ~= nil or err ~= nil end, "snapshot arrives")
  return snap, err
end

--- Capture notifications during fn.
function M.capture_notify(fn)
  local seen, orig = {}, vim.notify
  vim.notify = function(msg, level) seen[#seen + 1] = { msg = msg, level = level } end
  local ok, err = pcall(fn)
  vim.notify = orig
  if not ok then error(err, 0) end
  return seen
end

return M
