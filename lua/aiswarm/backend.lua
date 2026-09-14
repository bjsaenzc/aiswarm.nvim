-- Asynchronous typed backend client (SDD-044). Every call is argv-based (no shell), has a
-- timeout, delivers exactly one structured callback and is owned by the project generation.
local M = {}
local function A() return require("aiswarm") end
local project = require("aiswarm.project")

M.stats = { calls = 0, cancelled = 0, timeouts = 0 }
--- Injectable transport for fixtures: function(argv, opts, on_done) -> handle{kill=fn} | nil, err
M.client = nil

local DECODE = { luanil = { object = true, array = true } }

local function default_client(argv, opts, on_done)
  local ok, job = pcall(vim.system, argv, { text = true, env = opts.env, stdin = opts.stdin, timeout = opts.timeout_ms }, on_done)
  if not ok then return nil, tostring(job) end
  return job
end

---@class aiswarm.BackendResult
---@field ok boolean
---@field data any        decoded JSON (or raw stdout when json=false)
---@field error? string
---@field code? integer
---@field stale? boolean  project changed while running
---@field cancelled? boolean
---@field timed_out? boolean
---@field stderr? string

--- Run a backend command. Returns a handle with :cancel().
---@param args string[] subcommand and flags (no --json needed)
---@param opts? { json?: boolean, timeout_ms?: number, stdin?: string, env?: table, silent?: boolean }
---@param cb fun(res: aiswarm.BackendResult)
function M.call(args, opts, cb)
  opts = opts or {}
  M.stats.calls = M.stats.calls + 1
  local json = opts.json ~= false
  local argv = A().cmd(args)
  if json then argv[#argv + 1] = "--json" end
  local token, root = project.token(), A().root()
  local delivered = false
  local handle = { done = false }
  local function deliver(res)
    if delivered then return end
    delivered, handle.done = true, true
    if not project.alive(token) or root ~= A().root() then
      res = { ok = false, error = "project changed while the command was running", stale = true, code = 125 }
    end
    if cb then
      local ok, err = pcall(cb, res)
      if not ok then A().err("backend callback failed: " .. tostring(err)) end
    end
  end
  local on_done = vim.schedule_wrap(function(o)
    if handle.cancelled then M.stats.cancelled = M.stats.cancelled + 1; return deliver({ ok = false, cancelled = true, error = "cancelled", code = o and o.code }) end
    if o.code == 124 and (o.signal == 15 or o.signal == 9 or (o.stdout == "" and o.stderr == "")) then
      M.stats.timeouts = M.stats.timeouts + 1
      return deliver({ ok = false, timed_out = true, error = ("timed out after %d ms"):format(opts.timeout_ms or A().config.command_timeout_ms), code = 124 })
    end
    local res = { code = o.code, stderr = o.stderr }
    if o.code == 0 then
      if json then
        local ok, data = pcall(vim.json.decode, o.stdout or "", DECODE)
        if ok then res.ok, res.data = true, data
        else res.ok, res.error, res.data = false, "invalid JSON from backend", o.stdout end
      else res.ok, res.data = true, o.stdout end
    else
      res.ok = false
      local ok, err = pcall(vim.json.decode, vim.trim(o.stderr or ""), DECODE)
      if ok and type(err) == "table" and err.error then res.error, res.code = err.error, err.code or o.code
      else res.error = A().failure(o) end
    end
    deliver(res)
  end)
  local env = vim.tbl_extend("force", A().env(), opts.env or {})
  local client = M.client or default_client
  local job, err = client(argv, { env = env, stdin = opts.stdin, timeout_ms = opts.timeout_ms or A().config.command_timeout_ms }, on_done)
  if not job then
    vim.schedule(function() deliver({ ok = false, error = "could not start backend: " .. tostring(err), code = 127 }) end)
    return handle
  end
  handle.job = job
  function handle.cancel()
    if handle.done or handle.cancelled then return end
    handle.cancelled = true
    pcall(function() job:kill(15) end)
  end
  return handle
end

--- Convenience: call and notify errors unless silent.
function M.run(args, opts, cb)
  return M.call(args, opts, function(res)
    if not res.ok and not res.stale and not res.cancelled and not (opts and opts.silent) then A().err(res.error or "backend failed") end
    if cb then cb(res) end
  end)
end

return M
