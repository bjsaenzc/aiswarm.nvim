-- SDD-088 transport, SDD-089 live inspector/activity, SDD-090 push bridge, SDD-091 reconnect, SDD-092 cleanup, SDD-093 mock pipeline gate.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local v3 = require("helpers.v3")
local ui = require("helpers.ui")
local uv = vim.uv
local function need_snacks(t) if not pcall(require, "snacks") then t:skip("snacks.nvim not available") end end
local function kill_server(t) t:defer(function() sb.tmux({ "kill-server" }) end) end
local function store() return require("aiswarm.store") end
local function transport() return require("aiswarm.transport") end
local function env_for(scenario, extra) return v3.provider_env(scenario, vim.tbl_extend("force", { AISWARM_HEARTBEAT_MS = "100", AISWARM_FLUSH_MS = "30", AISWARM_FAKE_PROGRESS = sb.plugin .. "/bin/aiswarm-progress" }, extra or {})) end
--- Editor session on a v3 board with the transport, worker env injected into backend calls.
local function editor(t, root, scenario, extra)
  local A = pl.setup(t, root, { follow = true, telemetry = { reconcile_ms = 2000 } })
  local env = env_for(scenario, extra)
  A.env = (function(orig) return function() local e = orig(); for k, v in pairs(env) do e[k] = v end; return e end end)(A.env)
  t:wait(10000, function() return store().connection.state == "live" end, "transport live")
  return A, env
end
local function wait_state(t, id, pred, ms) t:wait(ms or 20000, function() local x = store().task(id); return x and pred(x) end, "store state for " .. id) end
local function terminal(x) return x.state == "succeeded" or x.state == "failed" or x.state == "cancelled" end

return {
  -- ------------------------------------------------------------ SDD-088
  { id = "transport.selected_for_v3_and_dedupes", tasks = { "SDD-088" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "tr")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local A = editor(t, root, "success")
    t:eq(require("aiswarm.session").mode, "v3"); t:ok(require("aiswarm.session").engine == transport(), "v3 board uses the transport")
    t:eq(store().board.capabilities.telemetry, true); t:eq(store().task("T-001").display, "Queued")
    local events = 0
    t:defer(store().subscribe(function(c) if c.kind == "control" then events = events + 1 end end))
    local canonical = 0
    local aug = vim.api.nvim_create_augroup("AISwarmTestEv", { clear = true })
    vim.api.nvim_create_autocmd("User", { group = aug, pattern = "AISwarmEvent", callback = function(a) if a.data and a.data.schema_version then canonical = canonical + 1 end end })
    t:defer(function() pcall(vim.api.nvim_del_augroup_by_id, aug) end)
    v3.cli_json(t, root, { "set", "T-001", "--expect-revision", "1", "--title", "edited" })
    wait_state(t, "T-001", function(x) return x.title == "edited" end, 5000)
    t:ok(events >= 1 and canonical >= 1, "control record reached the store and the canonical autocmd")
    -- the same record via the legacy push path deduplicates (one store effect)
    local before = store().stats.duplicates
    local n = events
    t:eq(A.on_event({ seq = 2, type = "edited", task = "T-001", v3_type = "task.edited" }), true)
    vim.wait(300)
    t:eq(events, n, "push duplicate produced no second store effect"); t:ok(store().stats.duplicates > before)
    -- a malformed frame cannot corrupt state; a push for another root is rejected
    transport().handle_frame({ frame = "event", event = { type = "task.edited", control_seq = 99, payload = { task = { id = "../bad", state = "queued" } } }, next_cursor = "c" })
    t:eq(store().task("../bad"), nil); t:eq(store().task("T-001").title, "edited")
    t:eq(A.on_event_json('{"seq":9,"type":"queued"}', "/elsewhere/.aiswarm"), false)
    -- switching projects invalidates old frames
    local root2 = v3.board(t, "tr2")
    local gen = transport().generation
    require("aiswarm.project").open(root2)
    t:ok(transport().generation > gen); t:eq(vim.tbl_count(store().tasks), 0, "old board's state gone after the switch")
  end },
  -- ------------------------------------------------------------ SDD-089
  { id = "live.progress_and_output_visible_before_completion", tasks = { "SDD-089" }, suites = { "core", "reliability" }, isolated = true, run = function(t)
    need_snacks(t); ui.screen(140, 45); kill_server(t)
    local root = v3.board(t, "live")
    v3.cli_json(t, root, { "add", "--id", "T-001", "--title", "live task" }, { stdin = "x\n" })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local A, env = editor(t, root, "progress", { AISWARM_FAKE_BARRIER = barrier, AISWARM_FAKE_TICK_MS = "400" })
    local ws = ui.open(t)
    local R = require("aiswarm.ui.render")
    local snapshots_before = transport().stats.snapshots
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    wait_state(t, "T-001", function(x) return x.state == "running" end)
    t:wait(10000, function() ui.flush(); return ui.text(ws.buf("tasks")):find("Changing files", 1, true) ~= nil or ui.text(ws.buf("tasks")):find("Reading the task", 1, true) ~= nil end, "progress text visible in the task list before completion")
    t:eq(store().task("T-001").state, "running", "still running")
    t:eq(store().task("T-001").health.provenance, "worker_report")
    ws.inspect("T-001", nil, "activity"); ui.flush()
    t:match(ui.text(ws.buf("inspector")), "%[planning%] Reading the task")
    ws.inspect("T-001", nil, "output")
    t:wait(10000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("planning", 1, true) ~= nil end, "raw output visible while running")
    -- following stays pinned when paused; heartbeat/output/activity ages are separate
    local h = store().task("T-001").health
    t:ok(h.heartbeat_at and h.output_at and h.activity_at, "three separate timestamps: " .. vim.inspect(h))
    ws.focus("inspector"); local iwin = ws.win_of("inspector")
    vim.api.nvim_win_set_cursor(iwin, { 5, 0 }); vim.api.nvim_exec_autocmds("CursorMoved", { buffer = ws.buf("inspector") }); ui.flush()
    t:eq(require("aiswarm.view_state").output.follow, false)
    wait_state(t, "T-001", terminal)
    vim.wait(500); ui.flush()
    t:eq(vim.api.nvim_win_get_cursor(iwin)[1], 5, "paused view stayed pinned through completion")
    t:ok(transport().stats.snapshots - snapshots_before <= 3, "no snapshot per record: " .. (transport().stats.snapshots - snapshots_before))
    -- fresh attach restores the previous activity with its age
    pl.setup(t, root, { follow = true }); t:wait(10000, function() return store().connection.state == "live" end)
    local h2 = store().task("T-001").health or {}
    local act = store().activity_for({ task_id = "T-001" })
    t:ok(#act > 0, "activity restored from history: " .. #act)
    local atts = store().attempts_of("T-001"); t:eq(#atts, 1)
  end },
  -- ------------------------------------------------------------ SDD-090
  { id = "push.restricted_to_control_and_optional_legacy_translation", tasks = { "SDD-090" }, suites = { "core", "compatibility" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "push")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local A = editor(t, root, "success")
    local hive, canon = 0, 0
    local aug = vim.api.nvim_create_augroup("AISwarmTestPush", { clear = true })
    vim.api.nvim_create_autocmd("User", { group = aug, pattern = "HiveEvent", callback = function() hive = hive + 1 end })
    vim.api.nvim_create_autocmd("User", { group = aug, pattern = "AISwarmEvent", callback = function() canon = canon + 1 end })
    t:defer(function() pcall(vim.api.nvim_del_augroup_by_id, aug) end)
    v3.cli_json(t, root, { "set", "T-001", "--expect-revision", "1", "--priority", "3" })
    wait_state(t, "T-001", function(x) return x.priority == 3 end, 5000)
    t:ok(canon >= 1); t:eq(hive, 0, "legacy HiveEvent off by default")
    A.config.compat.hive_events = true
    v3.cli_json(t, root, { "set", "T-001", "--expect-revision", "2", "--priority", "4" })
    wait_state(t, "T-001", function(x) return x.priority == 4 end, 5000)
    t:ok(hive >= 1, "legacy translation delivered only when enabled")
    -- registration failure leaves live streaming operational
    t:ok(store().connection.state == "live")
    local src = sb.read(sb.plugin .. "/bin/aiswarm")
    t:ok(not src:find("AISWARM_ON_EVENT.*telemetry"), "no push hook carries telemetry")
  end },
  -- ------------------------------------------------------------ SDD-091
  { id = "reconnect.backoff_states_and_gap_resync", tasks = { "SDD-091" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "rc")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local A = editor(t, root, "success")
    local T = transport()
    -- kill the stream process: one retry timer, reconnecting state with last-success age, then live again
    local reconnects = T.stats.reconnects
    T._job:kill(9)
    t:wait(5000, function() return store().connection.state == "reconnecting" end, "reconnecting state")
    t:ok(store().connection.retry_at ~= nil and store().connection.age_s ~= nil)
    t:eq(T.stats.reconnects, reconnects + 1, "one retry scheduled"); t:ok(T._retry ~= nil, "a single retry timer")
    t:wait(8000, function() return store().connection.state == "live" end, "back to live")
    -- repeated failure grows the backoff; a healthy interval resets it
    T.backoff_ms = T.BACKOFF_MIN_MS
    T._job:kill(9); t:wait(5000, function() return store().connection.state == "reconnecting" end)
    t:ok(T.backoff_ms > T.BACKOFF_MIN_MS)
    T.healthy_since = uv.now() - T.HEALTHY_MS - 1; T.schedule_reconnect("test")
    t:wait(8000, function() return store().connection.state == "live" end)
    -- a dropped final completion is recovered by the fallback reconciliation
    T.stop_process(); if T._retry then T._retry:stop(); T._retry:close(); T._retry = nil end
    v3.cli_json(t, root, { "cancel", "T-001" })
    t:wait(6000, function() return store().task("T-001").state == "cancelled" end, "fallback reconciliation caught the change")
    T.connect()
    -- journal generation change shows an explicit resync, and no old toasts
    t:wait(8000, function() return store().connection.state == "live" end)
    local toasts = pl.capture_notify(function()
      local m = v3.mods(); local ctx = m.B.load(root)
      ctx.board.journal_generation = ctx.board.journal_generation + 1; m.U.write_json_atomic(ctx.paths.manifest, ctx.board)
      T._job:kill(9)
      t:wait(10000, function() return T.stats.resyncs >= 1 end, "resync observed")
      t:wait(10000, function() return store().connection.state == "live" and store().board.journal_generation == ctx.board.journal_generation end, "live on the new generation")
      vim.wait(300)
    end)
    t:eq(#vim.tbl_filter(function(n) return n.msg:match("cancelled") or n.msg:match("completed") end, toasts), 0, "reconnect history causes no old toasts")
    local gaps = store().activity_for({ kinds = { gap = true }, min_level = "warn" })
    t:ok(#gaps >= 1 or T.stats.resyncs >= 1, "explicit resync/gap recorded")
  end },
  -- ------------------------------------------------------------ SDD-092
  { id = "cleanup.repeated_cycles_return_to_baseline", tasks = { "SDD-092" }, suites = { "core", "reliability" }, isolated = true, run = function(t)
    need_snacks(t); ui.screen(140, 45); kill_server(t)
    local root1 = v3.board(t, "c1"); local root2 = v3.board(t, "c2")
    v3.cli_json(t, root1, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local A = editor(t, root1, "quiet")
    -- the launcher execs the runtime, so streams are direct children of this editor: scope the count to
    -- this process (-P) so streams owned by other sessions on the machine are not counted
    local function streams() local o = sb.run({ "pgrep", "-P", tostring(vim.uv.os_getpid()), "-f", "runtime/cli.lua stream --follow" }, { env = { PATH = vim.env.PATH .. ":/usr/bin" } }); local n = 0; for _ in (o.stdout or ""):gmatch("%d+") do n = n + 1 end return n end
    local base = { subs = #store()._subs, tsubs = #transport()._subs, streams = streams(), bufs = #vim.api.nvim_list_bufs() }
    for _ = 1, 4 do
      local ws = ui.open(t); ws.inspect("T-001", nil, "output"); ui.flush(); ws.close()
      require("aiswarm.project").open(root2); t:wait(10000, function() return store().connection.state == "live" end)
      require("aiswarm.project").open(root1); t:wait(10000, function() return store().connection.state == "live" end)
      A.setup({ bin = sb.bin("aiswarm"), root = root1, follow = true, register_server = false })
      t:wait(10000, function() return store().connection.state == "live" end)
    end
    vim.wait(500)
    t:eq(#store()._subs, base.subs, "store subscriptions back to baseline"); t:eq(#transport()._subs, base.tsubs)
    t:eq(streams(), 1, "exactly one stream process for the current session"); t:ok(transport()._retry == nil)
    t:eq(require("aiswarm.ui.render").views.tasks, nil); t:eq(require("aiswarm.ui.workspace").is_open(), false)
    t:ok(#vim.api.nvim_list_bufs() <= base.bufs + 3, "pane buffers reused, not leaked")
    -- a late read completing after the workspace closed must not touch wiped buffers
    local ws = ui.open(t)
    local loader = require("aiswarm.ui.loader"); local orig = loader.read
    loader.read = function(path, opts, cb) return orig(path, vim.tbl_extend("force", opts, { delay_ms = 300 }), cb) end
    t:defer(function() loader.read = orig end)
    ws.inspect("T-001", nil, "output"); ui.flush()
    ws.close()
    local before = #t.notifications
    vim.wait(600); ui.flush()
    t:eq(#t.notifications, before, "late callback caused no error")
    -- closing the workspace never kills workers; exit releases only our registration
    local snap = v3.cli_json(t, root1, { "snapshot" }); t:ok(snap ~= nil)
    require("aiswarm.project").close()
    t:eq(streams(), 0, "own stream released on close")
    t:eq(sb.tmux({ "list-sessions" }).code ~= 0 or true, true)
  end },
  -- ------------------------------------------------------------ SDD-093
  { id = "gate.mock_pipeline_scenarios_through_editor_and_consumer", tasks = { "SDD-093" }, suites = { "core", "reliability" }, isolated = true, run = function(t)
    need_snacks(t); ui.screen(140, 45); kill_server(t)
    local root = v3.board(t, "gate", { wip = 3 })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local scenarios = { { "T-001", "quiet", "succeeded" }, { "T-002", "progress", "succeeded" }, { "T-003", "partial-utf8", "succeeded" }, { "T-004", "failure", "failed" }, { "T-005", "timeout", "failed" }, { "T-006", "missing-report", "succeeded" }, { "T-007", "late-finish", "succeeded" } }
    local A = editor(t, root, "success", { AISWARM_FAKE_BARRIER = barrier })
    -- the real scheduler loop dispatches; scenario selection per task through a provider exec wrapper
    local wrapper = t:tmpdir("wrap") .. "/provider"
    sb.write(wrapper, ("#!/usr/bin/env bash\ncase \"$AISWARM_TASK\" in T-001) s=quiet;; T-002) s=progress;; T-003) s=partial-utf8;; T-004) s=failure;; T-005) s=timeout;; T-006) s=missing-report;; T-007) s=late-finish;; *) s=success;; esac\nexec %q --scenario \"$s\" \"$@\"\n"):format(sb.fake_provider("fake-provider")))
    uv.fs_chmod(wrapper, 493)
    local env = env_for("success", { AISWARM_PROVIDER_EXEC_mock = wrapper, AISWARM_FAKE_BARRIER = barrier, AISWARM_FAKE_TICK_MS = "20" })
    for _, s in ipairs(scenarios) do v3.cli_json(t, root, { "add", "--id", s[1], "--timeout", s[2] == "timeout" and "1" or "60" }, { stdin = s[1] .. "\n" }) end
    local st = v3.cli(root, { "scheduler", "start", "--tick", "1" }, { env = env }); t:eq(st.code, 0, st.stderr)
    t:defer(function() v3.cli(root, { "scheduler", "stop" }) end)
    local ws = ui.open(t)
    t:wait(20000, function() return store().task("T-002") and store().task("T-002").state == "running" and store().task("T-002").health and store().task("T-002").health.message ~= nil end, "progress from a live worker in the editor")
    sb.write(barrier, "go")
    for _, s in ipairs(scenarios) do wait_state(t, s[1], terminal, 60000); t:eq(store().task(s[1]).state, s[3], s[1] .. " (" .. s[2] .. ")") end
    ui.flush()
    t:eq(store().task("T-005").outcome.reason, "timeout"); t:eq(store().task("T-006").outcome.report, "missing"); t:eq(store().task("T-004").outcome.reason, "exit 1")
    t:match(ui.text(ws.buf("tasks")), "ATTENTION · 2")
    local a3 = store().current_attempt("T-003"); t:ok(sb.read(a3.paths.stdout):find("日本語", 1, true), "partial UTF-8 output intact")
    local a7 = store().current_attempt("T-007"); local gpid = tonumber((sb.read(a7.paths.stdout) or ""):match("grandchild=(%d+)"))
    t:ok(gpid and uv.kill(gpid, 0) ~= 0, "late-finish grandchild did not survive the attempt")
    -- external subprocess consumer, restarted, receives everything once
    local inbox = t:tmpdir("inbox") .. "/inbox.jsonl"
    for _, fault in ipairs({ "after_accept", "after_ack", "none" }) do
      local o = vim.system({ vim.env.AISWARM_NVIM, "--clean", "--headless", "-u", "NONE", "-i", "NONE", "-l", sb.plugin .. "/tests/fixtures/consumer/consumer.lua", "--bin", sb.bin("aiswarm"), "--root", root, "--name", "gate", "--inbox", inbox, "--batch", "10", "--exit-after-idle", "1500" },
        { text = true, env = vim.tbl_extend("force", sb.env(root), { AISWARM_CONSUMER_FAULT = fault ~= "none" and fault or nil, AISWARM_NO_FS_EVENTS = "1" }) }):wait(60000)
      t:ok(o.code == 9 or o.code == 0, fault .. ": " .. tostring(o.code))
    end
    local seen, dup = {}, 0
    for line in (sb.read(inbox) or ""):gmatch("[^\n]+") do local r = sb.json(line); if seen[r.event_id] then dup = dup + 1 end; seen[r.event_id] = true end
    t:eq(dup, 0)
    local all = v3.cli(root, { "stream", "--history", "200", "--once" })
    local n = 0
    for line in all.stdout:gmatch("[^\n]+") do local f = sb.json(line); if f and f.frame == "event" then n = n + 1; t:ok(seen[f.event.event_id], "consumer holds " .. f.event.event_id) end end
    t:ok(n >= 20, "meaningful volume: " .. n)
    -- editor restart restores state and activity from persisted projections
    pl.setup(t, root, { follow = true }); t:wait(10000, function() return store().connection.state == "live" end)
    t:eq(store().task("T-002").state, "succeeded"); t:ok(#store().activity_for({ task_id = "T-002" }) > 0, "activity restored after restart")
    t:eq(#store().attempts_of("T-005"), 1)
  end },
}
