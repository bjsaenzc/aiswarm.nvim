-- SDD-004 disposable prototype of a headless worker. Invoked as
--   nvim --clean --headless --noplugin -u NONE -i NONE -l worker.lua <exe> <out.jsonl> <exit-file> [scenario]
-- It spawns the provider in its own process group, streams stdout/stderr into
-- JSONL records (with a monotonic write timestamp), emits a heartbeat every
-- 200 ms and records the exit. SIGTERM to the worker terminates the whole
-- provider process group before the worker exits.
local uv = vim.uv
local exe, out_path, exit_path, scenario = arg[1], arg[2], arg[3], arg[4] or "success"
local out = assert(io.open(out_path, "a"))
local seq = 0
local function record(type_, fields)
  seq = seq + 1
  fields = fields or {}
  fields.seq, fields.type, fields.t_ns = seq, type_, uv.hrtime()
  fields.wall = uv.clock_gettime("realtime")
  out:write(vim.json.encode(fields), "\n"); out:flush()
end
local stdout, stderr = uv.new_pipe(false), uv.new_pipe(false)
local env = {}
for k, v in pairs(vim.fn.environ()) do env[#env + 1] = k .. "=" .. v end
env[#env + 1] = "AISWARM_FAKE_SCENARIO=" .. scenario
local proc, pid
local function on_exit(code, signal)
  record("exit", { code = code, signal = signal })
  local f = assert(io.open(exit_path, "w")); f:write(vim.json.encode({ code = code, signal = signal })); f:close()
  out:close()
  os.exit(0)
end
proc, pid = uv.spawn(exe, { args = {}, env = env, stdio = { nil, stdout, stderr }, detached = true }, on_exit)
record("spawned", { pid = pid })
local function reader(name)
  return function(err, data)
    if err then record("read_error", { stream = name, error = err }) end
    if data then record("output", { stream = name, bytes = #data, preview = data:sub(1, 80) }) end
  end
end
stdout:read_start(reader("stdout")); stderr:read_start(reader("stderr"))
local cancel_path = out_path .. ".cancel"
local terminating = false
local function terminate(reason)
  if terminating then return end
  terminating = true
  record("terminate_requested", { reason = reason })
  -- Kill the whole provider process group; the worker put it in its own group with detached=true.
  pcall(uv.kill, -pid, "sigterm")
  local t = uv.new_timer(); t:start(300, 0, function() pcall(uv.kill, -pid, "sigkill") end)
end
local hb = uv.new_timer()
hb:start(50, 50, function()
  if uv.fs_stat(cancel_path) then terminate("cancel_request") end
end)
local hb2 = uv.new_timer(); hb2:start(200, 200, function() record("heartbeat", { pid = pid, alive = uv.kill(pid, 0) == 0 }) end)
-- Signals are a fallback only: Neovim installs its own deadly-signal handler, so the
-- production worker uses the cancel request file above as the authoritative channel.
local sig = uv.new_signal(); sig:start("sigterm", function() terminate("sigterm") end)
uv.run("default")
