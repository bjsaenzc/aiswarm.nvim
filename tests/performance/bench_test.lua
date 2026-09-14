-- SDD-097: the specified performance envelope. Duration from AISWARM_BENCH_SECONDS (suite default 20 s;
-- scripts/bench-aiswarm.sh runs the exact 10-minute workload). Targets are asserted, never lowered.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local v3 = require("helpers.v3")
local ui = require("helpers.ui")
local uv = vim.uv
local function need_snacks(t) if not pcall(require, "snacks") then t:skip("snacks.nvim not available") end end
local function p95(list) if #list == 0 then return nil end local s = vim.deepcopy(list); table.sort(s); return s[math.max(1, math.ceil(#s * 0.95))] end
local function wall_ms() local s, u = uv.gettimeofday(); return s * 1000 + math.floor(u / 1000) end
local function iso_ms(iso) local t = require("aiswarm.runtime.util").parse_iso(iso); return t and math.floor(t * 1000) or nil end
local function rss_kb(pid) local o = vim.system({ "ps", "-o", "rss=", "-p", tostring(pid) }, { text = true }):wait(); return tonumber(vim.trim(o.stdout or "")) or 0 end

return {
  { id = "bench.reference_load_envelope", tasks = { "SDD-097" }, suites = { "performance" }, isolated = true, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    t:defer(function() sb.tmux({ "kill-server" }) end)
    local seconds = tonumber(vim.env.AISWARM_BENCH_SECONDS) or 20
    local workers = tonumber(vim.env.AISWARM_BENCH_WORKERS) or 10
    local tasks_n = tonumber(vim.env.AISWARM_BENCH_TASKS) or 1000
    local task_s = tonumber(vim.env.AISWARM_BENCH_TASK_SECONDS) or math.max(5, math.floor(seconds * workers / tasks_n))
    local m = v3.mods()
    local root, ctx = v3.board(t, "bench", { wip = workers })
    local t0 = uv.hrtime()
    v3.bulk_add(ctx, tasks_n, { prompt = "bench" })
    local add_ms = (uv.hrtime() - t0) / 1e6
    -- one ordinary add on the populated board: the per-command cost the ADR budget bounds (≤ 250 ms p95)
    local adds = {}
    for i = 1, 5 do local s = uv.hrtime(); m.O.add(ctx, { id = ("X-%03d"):format(i), prompt = "single\n" }); adds[#adds + 1] = (uv.hrtime() - s) / 1e6 end
    -- exact-rate Lua generator; workers cycle between attempts, so the achieved aggregate is recorded
    local env = v3.provider_env("bench", { AISWARM_PROVIDER_EXEC_mock = sb.plugin .. "/tests/fixtures/providers/bench-provider",
      AISWARM_BENCH_TASK_SECONDS = tostring(task_s), AISWARM_BENCH_PROGRESS_PER_S = tostring(math.floor(200 / workers)),
      AISWARM_BENCH_OUTPUT_BPS = tostring(math.floor(1048576 / workers)), AISWARM_HEARTBEAT_MS = "5000", AISWARM_FLUSH_MS = "100" })
    local A = pl.setup(t, root, { follow = true, telemetry = { reconcile_ms = 10000 } })
    A.env = (function(orig) return function() local e = orig(); for k, v in pairs(env) do e[k] = v end; return e end end)(A.env)
    t:wait(10000, function() return require("aiswarm.store").connection.state == "live" end)
    local store, R = require("aiswarm.store"), require("aiswarm.ui.render")
    -- instrumentation: flushed record → store receipt; render batch durations; visible = receipt + next flush
    local receipt, batches, visible = {}, {}, {}
    local pending_visible = {}
    t:defer(store.subscribe(function(c)
      if c.kind == "activity" and c.record and c.record.raw and c.record.kind == "progress" then
        local o = iso_ms(c.record.raw.observed_at); if o then local now = wall_ms(); receipt[#receipt + 1] = now - o; pending_visible[#pending_visible + 1] = o end
      end
    end))
    local orig_flush = R.flush
    R.flush = function() local s = uv.hrtime(); orig_flush(); batches[#batches + 1] = (uv.hrtime() - s) / 1e6; if #pending_visible > 0 then local now = wall_ms(); for _, o in ipairs(pending_visible) do visible[#visible + 1] = now - o end; pending_visible = {} end end
    t:defer(function() R.flush = orig_flush end)
    -- editor open cost with the 1,000-task store (cached)
    local opens = {}
    for _ = 1, 10 do local s = uv.hrtime(); local ws = ui.open(t); opens[#opens + 1] = (uv.hrtime() - s) / 1e6; ws.close() end
    local ws = ui.open(t)
    ws.inspect("T-0001", nil, "output")
    -- external consumer alongside the editor
    local inbox = t:tmpdir("inbox") .. "/inbox.jsonl"
    local consumer = vim.system({ vim.env.AISWARM_NVIM, "--clean", "--headless", "-u", "NONE", "-i", "NONE", "-l", sb.plugin .. "/tests/fixtures/consumer/consumer.lua", "--bin", sb.bin("aiswarm"), "--root", root, "--name", "bench", "--inbox", inbox, "--batch", "50", "--exit-after-idle", "4000" },
      { text = true, env = vim.tbl_extend("force", sb.env(root), { AISWARM_NO_FS_EVENTS = "1" }) })
    local st = v3.cli(root, { "scheduler", "start", "--tick", "1" }, { env = env }); t:eq(st.code, 0, st.stderr)
    t:defer(function() v3.cli(root, { "scheduler", "stop" }) end)
    local started = uv.hrtime()
    local rss_samples, cpu_samples = {}, {}
    local editor_pid = uv.os_getpid()
    local deadline = uv.now() + seconds * 1000
    while uv.now() < deadline do
      vim.wait(1000, function() return false end, 50)
      ui.flush()
      local snap = store.counts()
      local pids = {}
      for _, a in pairs(store.attempts) do if a.state == "running" and a.worker and a.worker.pid then pids[#pids + 1] = a.worker.pid end end
      if #pids > 0 then
        local o = vim.system(vim.list_extend({ "ps", "-o", "rss=,%cpu=", "-p" }, { table.concat(pids, ",") }), { text = true }):wait()
        local total_rss, total_cpu, n = 0, 0, 0
        for rss, cpu in (o.stdout or ""):gmatch("(%d+)%s+([%d%.]+)") do total_rss = total_rss + tonumber(rss); total_cpu = total_cpu + tonumber(cpu); n = n + 1 end
        if n > 0 then rss_samples[#rss_samples + 1] = total_rss / n; cpu_samples[#cpu_samples + 1] = total_cpu end
      end
    end
    local elapsed_s = (uv.hrtime() - started) / 1e9
    consumer:wait(20000)
    -- consumer receipt latency
    local consumer_lat, consumer_n = {}, 0
    for line in (sb.read(inbox) or ""):gmatch("[^\n]+") do
      local r = sb.json(line)
      if r and r.type == "agent.progress" and r.observed_at and r.received_wall then consumer_n = consumer_n + 1; consumer_lat[#consumer_lat + 1] = r.received_wall - (iso_ms(r.observed_at) or r.received_wall) end
    end
    local warnings, discarded = 0, 0
    for _, a in pairs(store.attempts) do
      for l in (sb.read(a.paths.telemetry) or ""):gmatch("[^\n]+") do local r = sb.json(l); if r and r.type == "telemetry.warning" then warnings = warnings + 1; discarded = discarded + ((r.payload or {}).discarded_stdout or 0) end end
    end
    local sched_session = require("aiswarm.runtime.tmux").scheduler_session(store.board.board_id)
    local sched_pane = sb.tmux({ "capture-pane", "-p", "-t", "=" .. sched_session .. ":", "-S", "-30" }).stdout
    local per_attempt = {}
    for _, a in pairs(store.attempts) do local n = 0; for _ in (sb.read(a.paths.telemetry) or ""):gmatch("agent%.progress") do n = n + 1 end per_attempt[#per_attempt + 1] = a.task_id .. "=" .. n .. "/" .. a.state end
    table.sort(per_attempt)
    local result = {
      diagnostics = { scheduler_pane = sched_pane, progress_per_attempt = per_attempt },
      workload = { seconds = elapsed_s, workers = workers, tasks = tasks_n, task_seconds = task_s, progress_records_received = #receipt, records_per_s_received = #receipt / elapsed_s,
        target_records_per_s = 200, target_output_bytes_per_s = 1048576, tasks_finished = store.counts().finished + store.counts().attention, bulk_fixture_ms = add_ms,
        single_add_on_populated_board_p95_ms = p95(adds), running_at_end = store.counts().running, scheduler = store.scheduler.state, dispatch_report = v3.cli_json(t, root, { "scheduler", "status" }) },
      latency_ms = { flushed_to_store_p95 = p95(receipt), flushed_to_visible_p95 = p95(visible), flushed_to_consumer_p95 = p95(consumer_lat), samples = #receipt, consumer_samples = consumer_n, percentile_method = "nearest-rank" },
      ui_ms = { cached_open_p95 = p95(opens), render_batch_p95 = p95(batches), render_batches = #batches, marks = R.stats.marks, per_view = R.stats.view_ms },
      resources = { worker_rss_kb_avg = #rss_samples > 0 and (function() local s = 0; for _, v in ipairs(rss_samples) do s = s + v end return s / #rss_samples end)() or nil,
        workers_cpu_percent_max = #cpu_samples > 0 and math.max(unpack(cpu_samples)) or nil, editor_rss_kb = rss_kb(editor_pid), editor_lua_heap_kb = math.floor(collectgarbage("count")) },
      integrity = { dropped_activity = store.stats.dropped_activity, coalesced = 0, gap = store.activity.gap == true, telemetry_warnings = warnings, discarded_bytes = discarded, duplicates = store.stats.duplicates },
      host = { os = uv.os_uname().sysname .. " " .. uv.os_uname().release .. " " .. uv.os_uname().machine, nvim = tostring(vim.version()), cpus = #uv.cpu_info() },
    }
    sb.write(vim.env.AISWARM_TEST_RUN_DIR .. "/bench.json", vim.json.encode(result))
    t:log("bench", result)
    t:ok(#receipt > 0, "progress records were received")
    t:ok(result.latency_ms.flushed_to_visible_p95 <= 500, "p95 flushed→visible ≤ 500 ms: " .. tostring(result.latency_ms.flushed_to_visible_p95))
    t:ok(result.latency_ms.flushed_to_consumer_p95 and result.latency_ms.flushed_to_consumer_p95 <= 500, "p95 flushed→consumer ≤ 500 ms: " .. tostring(result.latency_ms.flushed_to_consumer_p95))
    t:ok(result.ui_ms.cached_open_p95 <= 100, "cached open p95 ≤ 100 ms: " .. tostring(result.ui_ms.cached_open_p95))
    t:ok(result.ui_ms.render_batch_p95 <= 16, "render batch p95 ≤ 16 ms: " .. tostring(result.ui_ms.render_batch_p95))
    t:ok(not result.resources.worker_rss_kb_avg or result.resources.worker_rss_kb_avg <= 80 * 1024, "worker RSS within the ADR 0001 budget (80 MiB under load): " .. tostring(result.resources.worker_rss_kb_avg))
    t:ok(result.resources.editor_rss_kb <= 512 * 1024, "editor RSS stays bounded (≤ 512 MiB): " .. result.resources.editor_rss_kb)
    t:ok(#store.activity.records <= store.LIMITS.activity_records, "editor activity bound holds")
    t:ok(result.workload.records_per_s_received >= 150 or seconds < 60, "achieved aggregate load at least 150 records/s on the full run: " .. result.workload.records_per_s_received)
  end },
}
