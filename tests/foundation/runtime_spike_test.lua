-- SDD-004: prove the headless worker runtime is viable. Results are written to
-- <run>/spike-measurements.json and summarized in docs/aiswarm-decisions/0001-worker-runtime.md.
local sb = require("helpers.sandbox")
local uv = vim.uv
local nvim = vim.env.AISWARM_NVIM
local worker = sb.plugin .. "/tests/fixtures/runtime_spike/worker.lua"
local exe = sb.fake_provider("fake-provider")
local M = {}
local measurements = {}
local function save() sb.write(vim.env.AISWARM_TEST_RUN_DIR .. "/spike-measurements.json", vim.json.encode(measurements)) end
local function nvim_args(script, args)
  return vim.list_extend({ nvim, "--clean", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n", "-l", script }, args or {})
end
local function rss_kb(pid)
  local o = vim.system({ "ps", "-o", "rss=", "-p", tostring(pid) }, { text = true }):wait()
  return tonumber(vim.trim(o.stdout or "")) or 0
end
local function spawn_worker(t, scenario, extra_env)
  local dir = t:tmpdir(scenario)
  local env = vim.tbl_extend("force", { PATH = vim.env.PATH, HOME = vim.env.HOME, XDG_CONFIG_HOME = vim.env.XDG_CONFIG_HOME,
    AISWARM_FAKE_TICK_MS = "5", AISWARM_FAKE_REPORT = dir .. "/report.md", AISWARM_FAKE_BARRIER = dir .. "/barrier", TMPDIR = vim.env.TMPDIR }, extra_env or {})
  local job = vim.system(nvim_args(worker, { exe, dir .. "/out.jsonl", dir .. "/exit.json", scenario }), { text = true, env = env })
  return job, dir
end
local function records(dir)
  local out = {}
  for line in (sb.read(dir .. "/out.jsonl") or ""):gmatch("[^\n]+") do out[#out + 1] = sb.json(line) end
  return out
end

return {
  { id = "spike.clean_startup_time", tasks = { "SDD-004" }, suites = { "core", "performance" }, run = function(t)
    local script = t:tmpdir("startup") .. "/noop.lua"; sb.write(script, "os.exit(0)\n")
    local samples = {}
    for _ = 1, 10 do
      local s = uv.hrtime(); vim.system(nvim_args(script), { env = { PATH = vim.env.PATH, HOME = vim.env.HOME } }):wait()
      samples[#samples + 1] = (uv.hrtime() - s) / 1e6
    end
    table.sort(samples)
    measurements.startup_ms = { min = samples[1], median = samples[5], max = samples[10], samples = samples }
    save(); t:log("startup ms", measurements.startup_ms)
    t:ok(samples[5] < 500, "median clean headless startup below 500ms: " .. samples[5])
  end },
  { id = "spike.sentinel_user_config_never_loaded", tasks = { "SDD-004" }, suites = { "core" }, run = function(t)
    local cfg = vim.env.XDG_CONFIG_HOME .. "/nvim"
    local marker = t:tmpdir("sentinel") .. "/touched"
    sb.write(cfg .. "/init.lua", ("local f = io.open(%q, 'w'); f:write('x'); f:close()\n"):format(marker))
    sb.write(cfg .. "/plugin/sentinel.lua", ("local f = io.open(%q, 'w'); f:write('x'); f:close()\n"):format(marker))
    t:defer(function() os.remove(cfg .. "/init.lua"); os.remove(cfg .. "/plugin/sentinel.lua") end)
    local job, dir = spawn_worker(t, "success")
    local o = job:wait(10000)
    t:eq(o.code, 0, o.stderr)
    t:ok(not sb.exists(marker), "sentinel user config/plugin never executed by the worker")
    t:ok(sb.exists(dir .. "/exit.json"))
  end },
  { id = "spike.records_stream_while_provider_runs", tasks = { "SDD-004" }, suites = { "core", "performance" }, run = function(t)
    local job, dir = spawn_worker(t, "quiet", { AISWARM_FAKE_TICK_MS = "50" })
    -- Provider blocks on the barrier; records (spawned + heartbeats) must appear before it exits.
    t:wait(3000, function() local r = records(dir); return #r >= 3 end, "records visible while the provider is still running")
    local before = records(dir)
    t:ok(not sb.exists(dir .. "/exit.json"), "provider has not exited yet")
    t:eq(before[1].type, "spawned"); t:eq(before[2].type, "heartbeat"); t:eq(before[2].alive, true)
    sb.write(dir .. "/barrier", "go")
    local o = job:wait(10000); t:eq(o.code, 0, o.stderr)
    local all = records(dir)
    t:eq(all[#all].type, "exit"); t:eq(all[#all].code, 0)
    measurements.streaming = { records_before_exit = #before, total = #all }; save()
  end },
  { id = "spike.record_to_reader_latency", tasks = { "SDD-004" }, suites = { "core", "performance" }, run = function(t)
    -- A reader polls the JSONL file (fs_stat + incremental read at 50 ms) and measures write→read latency.
    local job, dir = spawn_worker(t, "flood", { AISWARM_FAKE_LINES = "3000" })
    local path, offset, latencies, seen = dir .. "/out.jsonl", 0, {}, 0
    local buf = ""
    t:wait(10000, function()
      local st = uv.fs_stat(path)
      if st and st.size > offset then
        local fd = uv.fs_open(path, "r", 420); local data = uv.fs_read(fd, st.size - offset, offset); uv.fs_close(fd)
        offset = st.size; buf = buf .. data
        local now = uv.hrtime()
        while true do
          local nl = buf:find("\n", 1, true); if not nl then break end
          local rec = sb.json(buf:sub(1, nl - 1)); buf = buf:sub(nl + 1)
          if rec and rec.type == "output" then seen = seen + 1; latencies[#latencies + 1] = (now - rec.t_ns) / 1e6 end
        end
      end
      return sb.exists(dir .. "/exit.json") and st and offset >= st.size
    end, "flood run completes")
    job:wait(2000)
    table.sort(latencies)
    local p = function(q) return latencies[math.max(1, math.floor(#latencies * q))] end
    measurements.record_to_reader_ms = { samples = #latencies, p50 = p(0.5), p95 = p(0.95), max = latencies[#latencies], poll_ms = 10, output_records = seen }
    save(); t:log("latency", measurements.record_to_reader_ms)
    t:ok(#latencies > 0 and p(0.95) < 500, "p95 write→read latency under 500ms with 10ms polling: " .. tostring(p(0.95)))
  end },
  { id = "spike.process_tree_terminated_on_cancel", tasks = { "SDD-004" }, suites = { "core", "reliability" }, run = function(t)
    local job, dir = spawn_worker(t, "grandchild-hold")
    t:wait(5000, function() local r = records(dir); return #r >= 2 and r[2].type ~= nil and (sb.read(dir .. "/out.jsonl") or ""):find("grandchild=") ~= nil end)
    local grandchild
    for _, r in ipairs(records(dir)) do if r.type == "output" and r.preview:match("grandchild=(%d+)") then grandchild = tonumber(r.preview:match("grandchild=(%d+)")) end end
    t:ok(grandchild, "grandchild pid observed"); t:ok(uv.kill(grandchild, 0) == 0, "grandchild alive before cancel")
    sb.write(dir .. "/out.jsonl.cancel", "{}") -- cancel request file: the watchdog terminates the provider group
    local o = job:wait(5000)
    t:eq(o.code, 0, "worker exited cleanly after recording the provider exit")
    t:wait(2000, function() return uv.kill(grandchild, 0) ~= 0 end, "grandchild terminated with the process group")
    local exit = sb.json(sb.read(dir .. "/exit.json") or "null")
    t:ok(exit and (exit.signal ~= 0 or exit.code ~= 0), "provider exit recorded as terminated: " .. vim.inspect(exit))
    measurements.process_tree_kill = { grandchild_terminated = true, provider_exit = exit }; save()
  end },
  { id = "spike.ten_workers_footprint", tasks = { "SDD-004" }, suites = { "core", "performance" }, run = function(t)
    local jobs, dirs = {}, {}
    for i = 1, 10 do local j, d = spawn_worker(t, "quiet", { AISWARM_FAKE_TICK_MS = "20" }); jobs[i], dirs[i] = j, d end
    t:wait(5000, function() for _, d in ipairs(dirs) do if #records(d) < 2 then return false end end return true end)
    local total, per = 0, {}
    for _, j in ipairs(jobs) do local kb = rss_kb(j.pid); per[#per + 1] = kb; total = total + kb end
    local cpu = vim.system({ "ps", "-o", "%cpu=", "-p", table.concat(vim.tbl_map(function(j) return tostring(j.pid) end, jobs), ",") }, { text = true }):wait()
    local cpu_total = 0; for v in (cpu.stdout or ""):gmatch("[%d%.]+") do cpu_total = cpu_total + tonumber(v) end
    for _, d in ipairs(dirs) do sb.write(d .. "/barrier", "go") end
    for _, j in ipairs(jobs) do j:wait(5000) end
    measurements.ten_workers = { rss_kb_total = total, rss_kb_per_worker = per, cpu_percent_total_idle = cpu_total }; save()
    t:log("ten workers", measurements.ten_workers)
    t:ok(total / 10 < 100 * 1024, "average worker RSS under 100 MiB: " .. (total / 10 / 1024) .. " MiB")
  end },
}
