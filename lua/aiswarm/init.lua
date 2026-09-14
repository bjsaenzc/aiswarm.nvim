-- aiswarm.nvim — public API and backend runner.
local M = {}
local config = require("aiswarm.config")
local project = require("aiswarm.project")

M.config = vim.deepcopy(config.defaults)
M.project = project

-- ---------------------------------------------------------------- root and runner
--- Current board root (from the open session) or nil when no session is open.
function M.root()
  if project.current then return project.current.root end
  if not M._resolved then M._resolved = project.resolve(M.config) end
  return M._resolved.root
end

--- Child environment for the backend: canonical variables and the Neovim executable.
function M.env()
  local root = M.root()
  return { AISWARM_ROOT = root, AISWARM_NVIM = vim.v.progpath }
end

---@param args string[]
function M.cmd(args) return vim.list_extend({ M.config.bin }, args) end

--- Async backend call. cb receives the vim.SystemCompleted object on the main loop.
function M.run(args, cb)
  local root, token = M.root(), project.token()
  local done = vim.schedule_wrap(function(o)
    if not project.alive(token) or root ~= M.root() then
      o = { code = 125, stdout = "", stderr = "aiswarm project changed while the command was running" }
    end
    if cb then cb(o) elseif o.code ~= 0 then M.err(M.failure(o)) end
  end)
  local ok, job = pcall(vim.system, M.cmd(args), { text = true, env = M.env(), timeout = M.config.command_timeout_ms }, done)
  if ok then return job end
  done({ code = 127, stdout = "", stderr = tostring(job) })
end

function M.failure(o)
  local err = vim.trim(o.stderr or "")
  return err ~= "" and err or ("aiswarm exited with code " .. tostring(o.code))
end

--- Sync backend call with a timeout. Returns stdout, code, stderr.
function M.run_sync(args, ms)
  local ok, o = pcall(function() return vim.system(M.cmd(args), { text = true, env = M.env() }):wait(ms or 2000) end)
  if not ok then return "", 127, tostring(o) end
  return o.stdout or "", o.code, o.stderr or ""
end

-- ---------------------------------------------------------------- notifications
function M.notify(msg, level)
  if package.loaded["snacks"] and _G.Snacks and Snacks.notify then
    Snacks.notify(msg, { title = "aiswarm", level = level or vim.log.levels.INFO })
  else
    vim.notify(msg, level or vim.log.levels.INFO, { title = "aiswarm" })
  end
end
function M.err(msg) M.notify(msg, vim.log.levels.ERROR) end
function M.warn(msg) M.notify(msg, vim.log.levels.WARN) end

-- ---------------------------------------------------------------- setup
---@param opts? table
function M.setup(opts)
  if vim.fn.has("nvim-0.10.4") == 0 then return M.err("aiswarm.nvim requires Neovim 0.10.4+") end
  local resolved = config.resolve(opts)   -- raises on invalid settings before any job or file is created
  M.config, M._resolved = resolved, nil
  local r = project.resolve(resolved)
  M._resolved = r
  if r.root then
    project.open(r.root, { source = r.source })
  else
    project.close()
  end
  require("aiswarm.notify").attach()
  M._setup_done = true
  return M
end

-- ---------------------------------------------------------------- state access
function M.state() return require("aiswarm.session").state() end
--- Cached statusline text from the store: no subprocess or file I/O on redraw.
function M.statusline()
  local store = package.loaded["aiswarm.store"]
  if not store or not M._setup_done then return "" end
  if store.connection.state == "offline" or store.connection.state == "incompatible" then return "aiswarm: " .. store.connection.state end
  local c = store.counts()
  if c.all == 0 then return "" end
  local parts = {}
  if store.scheduler.paused then parts[#parts + 1] = "⏸" end
  if store.connection.state == "reconnecting" then parts[#parts + 1] = "…" end
  parts[#parts + 1] = ("R:%d A:%d ✓%d ✗%d"):format(c.queued, c.running, c.states.succeeded or 0, (c.states.failed or 0) + (c.states.cancelled or 0))
  if c.unacknowledged > 0 then parts[#parts + 1] = "!" .. c.unacknowledged end
  return table.concat(parts, " ")
end
--- Structured statusline data for custom components (cached, no I/O).
function M.status()
  local store = package.loaded["aiswarm.store"]
  if not store or not M._setup_done then return nil end
  local c = store.counts()
  return { counts = c, connection = store.connection.state, paused = store.scheduler.paused == true, attention = c.unacknowledged, text = M.statusline() }
end
function M.on_event(e) return M.state().on_event(e) end
function M.on_event_json(s, root) return M.state().on_event_json(s, root) end
function M.refresh(cb) return M.state().refresh(cb) end
function M.subscribe(fn) return M.state().subscribe(fn) end

-- ---------------------------------------------------------------- UI forwards
local function ui() return require("aiswarm.ui") end
function M.open(opts)      return ui().open(opts) end
function M.pick()          return ui().pick() end
function M.results()       return ui().results() end
function M.new(prefill)    return ui().new(prefill) end
M.add = M.new
function M.activity()      return ui().activity() end
function M.tail(id)        return ui().tail(id) end
function M.peek(id)        return ui().peek(id) end
function M.attach(id)      return ui().attach(id) end
M.go = M.attach
function M.kill(id)        return ui().kill(id) end
function M.cancel(id)      return ui().cancel(id) end
function M.retry(id)       return ui().retry(id) end
function M.inspect(id)     return ui().inspect(id) end
function M.output(id)      return ui().output(id) end
function M.report(id)      return ui().report(id) end
function M.toggle_pause()  return ui().toggle_pause() end
function M.scheduler(action) return ui().scheduler(action) end
function M.health()        return vim.cmd("checkhealth aiswarm") end

return M
