-- :AISwarm subcommand parser, completion and routing (SDD-012).
local M = {}
local function A() return require("aiswarm") end

---@type table<string, { run: fun(args: string[], a: table), ids?: boolean, desc: string }>
M.subcommands = {
  open      = { desc = "Open or focus the workspace",        run = function() A().open() end },
  pick      = { desc = "Search tasks",                        run = function() A().pick() end },
  new       = { desc = "Compose a task (range = context)",   run = function(args, a)
    local prefill, source
    if a and a.range and a.range > 0 then
      prefill = vim.api.nvim_buf_get_lines(0, a.line1 - 1, a.line2, false)
      source = { path = vim.api.nvim_buf_get_name(0), line1 = a.line1, line2 = a.line2 }
    end
    local legacy, fresh = false, false
    for _, w in ipairs(args or {}) do if w == "--legacy" then legacy = true elseif w == "--fresh" then fresh = true end end
    require("aiswarm.ui").new(prefill, { legacy = legacy, source = source, fresh = fresh })
  end },
  activity  = { desc = "Combined activity view",             run = function() A().activity() end },
  results   = { desc = "Reports picker",                      run = function() A().results() end },
  refresh   = { desc = "Request reconciliation",              run = function() A().refresh() end },
  project   = { desc = "Show/switch the project board",       run = function(args) require("aiswarm.ui.project").run(args) end },
  health    = { desc = "Health diagnostics",                  run = function() A().health() end },
  inspect   = { desc = "Inspect a task",     ids = true,      run = function(args) A().inspect(args[1]) end },
  output    = { desc = "Task output",        ids = true,      run = function(args) A().output(args[1]) end },
  report    = { desc = "Task report",        ids = true,      run = function(args) A().report(args[1]) end },
  attach    = { desc = "Attach tmux session", ids = true,     run = function(args) A().attach(args[1]) end },
  tail      = { desc = "Follow transcript",  ids = true,      run = function(args) A().tail(args[1]) end },
  peek      = { desc = "Preview output",     ids = true,      run = function(args) A().peek(args[1]) end },
  cancel    = { desc = "Cancel a task",      ids = true,      run = function(args) A().cancel(args[1]) end },
  retry     = { desc = "Retry a terminal task", ids = true,   run = function(args) A().retry(args[1]) end },
  kill      = { desc = "Legacy: cancel and requeue", ids = true, run = function(args) A().kill(args[1]) end },
  pause     = { desc = "Toggle dispatch pause",               run = function() A().toggle_pause() end },
  scheduler = { desc = "scheduler start|stop|pause|resume",  run = function(args)
    local action = args[1]
    if action ~= "start" and action ~= "stop" and action ~= "pause" and action ~= "resume" then
      return A().err("usage: AISwarm scheduler start|stop|pause|resume")
    end
    A().scheduler(action)
  end },
  init      = { desc = "Create a board",                      run = function(args) require("aiswarm.ui.project").init(args) end },
  migrate   = { desc = "Inventory/upgrade a legacy board",    run = function(args) require("aiswarm.ui.project").migrate(args) end },
}
M.order = { "open", "pick", "new", "activity", "results", "inspect", "output", "report", "attach", "cancel", "retry",
  "pause", "scheduler", "refresh", "project", "init", "migrate", "health", "tail", "peek", "kill" }

function M.complete_ids(lead)
  local ok, ids = pcall(function() return A().state().ids() end)
  if not ok then return {} end
  return vim.tbl_filter(function(id) return id:find(lead, 1, true) == 1 end, ids)
end

function M.complete(lead, line)
  local words = vim.split(vim.trim(line), "%s+")
  local n = #words - (lead == "" and 0 or 1)
  if n <= 1 then return vim.tbl_filter(function(s) return s:find(lead, 1, true) == 1 end, M.order) end
  local sub = M.subcommands[words[2]]
  if sub and sub.ids then return M.complete_ids(lead) end
  if words[2] == "scheduler" then return vim.tbl_filter(function(s) return s:find(lead, 1, true) == 1 end, { "start", "stop", "pause", "resume" }) end
  return {}
end

--- Run a subcommand. Unknown names fail clearly.
function M.dispatch(name, args, a)
  local sub = M.subcommands[name]
  if not sub then return A().err("unknown AISwarm subcommand: " .. tostring(name) .. " (see :AISwarm help)") end
  return sub.run(args or {}, a)
end

function M.run(a)
  local words = vim.split(vim.trim(a.args), "%s+", { trimempty = true })
  local name = table.remove(words, 1) or "open"
  if name == "help" then
    local lines = {}
    for _, n in ipairs(M.order) do lines[#lines + 1] = ("%-10s %s"):format(n, M.subcommands[n].desc) end
    return A().notify(table.concat(lines, "\n"))
  end
  return M.dispatch(name, words, a)
end

function M.register()
  vim.api.nvim_create_user_command("AISwarm", M.run, {
    nargs = "*", range = true, desc = "AI swarm workspace",
    complete = function(lead, line) return M.complete(lead, line) end,
  })
end

return M
