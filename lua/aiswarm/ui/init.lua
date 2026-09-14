-- UI facade: routes commands to the workspace, composer, pickers and actions.
local M = {}
local function A() return require("aiswarm") end
local function legacy() return require("aiswarm.legacy.ui") end
local function ws() return require("aiswarm.ui.workspace") end
local function actions() return require("aiswarm.ui.actions") end

function M.unavailable(action, needs)
  A().warn(("%s is not available yet: %s"):format(action, needs))
  return false
end

function M.open(opts)
  if ws().available() then return ws().open(opts) end
  return legacy().dashboard()
end
function M.pick()         return require("aiswarm.ui.picker").pick() end
function M.results()      return require("aiswarm.ui.results").pick() end
function M.new(prefill, opts)
  opts = opts or {}
  if prefill and opts.legacy then return require("aiswarm.ui.composer").open({ legacy_lines = prefill, source = opts.source }) end
  return require("aiswarm.ui.composer").open({ prefill = prefill, source = opts.source, fresh = opts.fresh })
end
function M.activity()
  if not ws().is_open() then ws().open({}) end
  if ws().mode == "medium" then ws().inspect(require("aiswarm.view_state").selected.task_id, nil, "activity") else ws().focus("activity") end
end
function M.tail(id)       return legacy().tail(id) end
function M.peek(id)       return legacy().peek(id) end
function M.attach(id)     actions().resolve_id(id, function(tid) actions().run("attach", actions().target(tid)) end) end
function M.kill(id)       return legacy().kill(id) end
function M.toggle_pause() return legacy().toggle_pause() end
function M.inspect(id)    actions().resolve_id(id, function(tid) actions().run("inspect", actions().target(tid)) end) end
function M.output(id)     actions().resolve_id(id, function(tid) actions().run("output", actions().target(tid)) end) end
function M.report(id)     actions().resolve_id(id, function(tid) actions().run("report", actions().target(tid)) end) end
function M.cancel(id)
  if not require("aiswarm.store").capability("cancel") then return M.unavailable("cancel", "a v3 board (legacy boards only support :AISwarmKill = cancel and requeue; run :AISwarm migrate --dry-run)") end
  actions().resolve_id(id, function(tid) actions().run("cancel", actions().target(tid)) end)
end
function M.retry(id)
  if not require("aiswarm.store").capability("retry") then return M.unavailable("retry", "a v3 board (run :AISwarm migrate --dry-run)") end
  actions().resolve_id(id, function(tid) actions().run("retry", actions().target(tid)) end)
end
function M.scheduler(action)
  local store = require("aiswarm.store")
  if action == "pause" or action == "resume" then
    local paused = store.scheduler.paused == true
    if (action == "pause") == paused then return A().notify("dispatch already " .. action .. "d") end
    return legacy().toggle_pause()
  end
  if not store.capability("attempts") then return M.unavailable("scheduler " .. tostring(action), "a v3 board with scheduler ownership (run :AISwarm migrate --dry-run)") end
  require("aiswarm.backend").call({ "scheduler", action }, { timeout_ms = 20000 }, function(res)
    if res.ok then
      local msg = type(res.data) == "table" and (res.data.message or ("scheduler " .. action)) or tostring(res.data)
      A().notify(msg); A().refresh()
    elseif not res.stale then A().err(res.error or ("scheduler " .. action .. " failed")) end
  end)
end

return M
