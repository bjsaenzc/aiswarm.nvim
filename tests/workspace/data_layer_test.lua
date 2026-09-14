-- SDD-044 backend client, SDD-045 adapter, SDD-046 store, SDD-047 view state, SDD-048 render scheduler, SDD-050 text.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local fx = require("fixtures.state.mixed_snapshot")

return {
  -- ------------------------------------------------------------ SDD-044
  { id = "backend.delayed_command_never_blocks", tasks = { "SDD-044" }, suites = { "core" }, run = function(t)
    local root = sb.legacy_board(t)
    local A = pl.setup(t, root)
    local backend = require("aiswarm.backend")
    local ticks, done = 0, nil
    local timer = vim.uv.new_timer(); timer:start(5, 5, function() ticks = ticks + 1 end); t:defer(function() timer:stop(); timer:close() end)
    backend.client = function(argv, opts, on_done)
      local job = vim.system({ "bash", "-c", "sleep 0.3; echo '{\"ok\":1}'" }, { text = true }, on_done); return job
    end
    t:defer(function() backend.client = nil end)
    backend.call({ "json" }, {}, function(res) done = res end)
    t:wait(3000, function() return done ~= nil end)
    t:eq(done.ok, true); t:eq(done.data, { ok = 1 })
    t:ok(ticks >= 20, "UI sentinel timer kept ticking during the call: " .. ticks)
  end },
  { id = "backend.timeout_and_start_failure_one_callback", tasks = { "SDD-044" }, suites = { "core" }, run = function(t)
    local root = sb.legacy_board(t)
    local A = pl.setup(t, root)
    local backend = require("aiswarm.backend")
    local calls = 0
    backend.client = function(argv, opts, on_done) return vim.system({ "sleep", "5" }, { text = true, timeout = opts.timeout_ms }, on_done) end
    t:defer(function() backend.client = nil end)
    local res
    backend.call({ "json" }, { timeout_ms = 150 }, function(r) calls = calls + 1; res = r end)
    t:wait(3000, function() return res ~= nil end)
    vim.wait(100)
    t:eq(calls, 1); t:eq(res.timed_out, true); t:match(res.error, "timed out")
    backend.client = function() return nil, "boom" end
    local res2; calls = 0
    backend.call({ "json" }, {}, function(r) calls = calls + 1; res2 = r end)
    t:wait(1000, function() return res2 ~= nil end)
    t:eq(calls, 1); t:eq(res2.code, 127); t:match(res2.error, "could not start")
    -- cancellation delivers exactly one callback
    backend.client = function(argv, opts, on_done) return vim.system({ "sleep", "5" }, { text = true }, on_done) end
    local res3; calls = 0
    local h = backend.call({ "json" }, {}, function(r) calls = calls + 1; res3 = r end)
    h.cancel()
    t:wait(2000, function() return res3 ~= nil end); vim.wait(50)
    t:eq(calls, 1); t:eq(res3.cancelled, true)
  end },
  { id = "backend.project_switch_suppresses_result", tasks = { "SDD-044" }, suites = { "core" }, run = function(t)
    local root1 = sb.legacy_board(t, "one"); local root2 = sb.legacy_board(t, "two")
    local A = pl.setup(t, root1)
    local backend = require("aiswarm.backend")
    local res
    backend.client = function(argv, opts, on_done) return vim.system({ "bash", "-c", "sleep 0.2; echo '{}'" }, { text = true }, on_done) end
    t:defer(function() backend.client = nil end)
    backend.call({ "json" }, {}, function(r) res = r end)
    require("aiswarm.project").open(root2)
    t:wait(2000, function() return res ~= nil end)
    t:eq(res.stale, true); t:eq(res.ok, false)
  end },
  { id = "backend.metacharacters_stay_literal", tasks = { "SDD-044" }, suites = { "core" }, run = function(t)
    local root = sb.legacy_board(t)
    local A = pl.setup(t, root)
    local backend = require("aiswarm.backend")
    local seen
    backend.client = function(argv, opts, on_done) seen = argv; return vim.system({ "true" }, {}, on_done) end
    t:defer(function() backend.client = nil end)
    local weird = "a b; rm -rf / $(x) `y` 'q' \"dq\" \\ é"
    backend.call({ "add", "--title", weird }, { json = false }, function() end)
    t:wait(1000, function() return seen ~= nil end)
    t:eq(seen[3], "--title"); t:eq(seen[4], weird, "argument passed literally, no shell")
  end },
  -- ------------------------------------------------------------ SDD-045
  { id = "adapter.legacy_snapshot_normalized_with_capabilities", tasks = { "SDD-045" }, suites = { "core", "compatibility" }, run = function(t)
    pl.unload(); require("aiswarm")
    local adapter = require("aiswarm.adapter")
    local meta = { api_version = 2, capabilities = { atomic_add = true }, seq = 3, paused = true, wip = 3, root = "/x/.aiswarm" }
    local tasks = { ["T-001"] = { id = "T-001", state = "active", title = "a", provider = "mock", started_at = "2026-01-01T00:00:00Z" },
      ["T-002"] = { id = "T-002", state = "failed", rc = "orphaned", ended_at = "2026-01-01T00:01:00Z", depends_on = {} },
      ["T-003"] = { id = "T-003", state = "ready", depends_on = { "T-002" } }, ["T-004"] = { id = "T-004", state = "done", rc = 0 } }
    local snap = adapter.normalize_snapshot(meta, tasks)
    local by = {}; for _, x in ipairs(snap.tasks) do by[x.id] = x end
    t:eq(by["T-001"].state, "running"); t:eq(by["T-001"].display, "Running"); t:eq(by["T-001"].legacy, true)
    t:eq(by["T-002"].state, "failed"); t:eq(by["T-002"].outcome.reason, "orphaned"); t:eq(by["T-002"].display, "Failed: orphaned")
    t:eq(by["T-003"].display, "Blocked"); t:eq(by["T-003"].blockers[1].text, "blocked by T-002 (failed)")
    t:eq(by["T-004"].state, "succeeded"); t:eq(by["T-004"].attempts, {}, "no attempt history fabricated for v2")
    t:eq(snap.capabilities.attempts, false); t:eq(snap.capabilities.cancel, false); t:eq(snap.capabilities.legacy, true)
    t:eq(snap.scheduler.paused, true); t:eq(snap.board.schema, "v2")
    local ev, act = adapter.normalize_event({ seq = 4, type = "progress", task = "T-001", note = "halfway", ts = "2026-01-01T00:02:00Z" }, "r")
    t:eq(ev.needs_refresh, false); t:eq(act.text, "halfway"); t:eq(act.provenance, "worker_report")
    local ev2 = adapter.normalize_event({ seq = 5, type = "done", task = "T-001", ts = "x" }, "r"); t:eq(ev2.needs_refresh, true)
  end },
  { id = "adapter.order_and_duplicates_preserved_no_initial_toast", tasks = { "SDD-045" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "a\n")
    local A, S = pl.setup(t, root); pl.refresh(t, A)
    local store = require("aiswarm.store")
    t:eq(vim.tbl_count(store.tasks), 1); t:eq(store.board.schema, "v2"); t:eq(store.connection.state, "live")
    t:eq(#store.activity.records, 0, "historical events produce no activity/toast at attach")
    local got = {}
    t:defer(store.subscribe(function(c) if c.kind == "control" then got[#got + 1] = c.type end end))
    A.on_event({ seq = 3, type = "message", task = "T-001", text = "x" })
    A.on_event({ seq = 2, type = "message", task = "T-001", text = "y" })
    A.on_event({ seq = 2, type = "message", task = "T-001", text = "y" })
    t:eq(#got, 2, "ordered delivery with duplicates dropped (2 then 3)")
    t:eq(store.stats.duplicates, 0, "the legacy engine already dropped the duplicate; the store saw it once")
    t:eq(store.seq, 3, "delivery cursor separate from snapshot cursor"); 
  end },
  { id = "adapter.v3_board_through_compat_read_has_attempts", tasks = { "SDD-045" }, suites = { "core", "compatibility" }, run = function(t)
    local v3 = require("helpers.v3")
    local root = v3.board(t, "v3adapt")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local A = pl.setup(t, root); pl.refresh(t, A)
    local store = require("aiswarm.store")
    t:eq(store.board.schema, "v3"); t:eq(store.capability("cancel"), true); t:eq(store.tasks["T-001"].legacy, false)
    t:eq(store.tasks["T-001"].revision, 1); t:eq(store.tasks["T-001"].display, "Queued")
  end },
  -- ------------------------------------------------------------ SDD-046
  { id = "store.idempotent_replay_and_selectors", tasks = { "SDD-046" }, suites = { "core" }, run = function(t)
    pl.unload(); require("aiswarm")
    local store = require("aiswarm.store"); store.reset()
    local snap = fx.snapshot(12)
    t:ok(store.apply_snapshot(snap)); local v1 = vim.deepcopy(store.tasks)
    t:ok(store.apply_snapshot(snap)); t:eq(store.tasks, v1, "idempotent")
    local g = store.grouped()
    t:eq(#g.groups.running, 2); t:eq(#g.groups.queued, 4); t:eq(#g.groups.attention, 2); t:eq(#g.groups.finished, 4)
    t:eq(store.counts().all, 12); t:eq(store.counts().blocked, 2)
    t:eq(store.grouped({ text = "日本語" }).shown, 3)
    t:eq(#store.attempts_of("T-001"), 1); t:eq(store.current_attempt("T-001").ordinal, 1)
    t:eq(store.grouped(), g, "selector cached until the version changes")
    store.apply_control({ event_id = "e1", type = "task.edited", task = vim.tbl_extend("force", snap.tasks[2], { title = "renamed", revision = 2 }) })
    t:eq(store.tasks["T-002"].title, "renamed"); t:ok(store.grouped() ~= g, "cache invalidated")
    t:eq(store.apply_control({ event_id = "e1", type = "task.edited", task = snap.tasks[2] }), false, "duplicate event id ignored"); t:eq(store.tasks["T-002"].title, "renamed")
    local bad = store.apply_snapshot({ tasks = { { id = "../x", state = "queued" } } }); t:eq(bad, false)
  end },
  { id = "store.attempt_identity_fence_and_subscriber_isolation", tasks = { "SDD-046" }, suites = { "core" }, run = function(t)
    pl.unload(); require("aiswarm")
    local store = require("aiswarm.store"); store.reset()
    store.apply_snapshot(fx.snapshot(3))
    local calls = { a = 0, b = 0 }
    local u1 = store.subscribe(function() calls.a = calls.a + 1; error("boom") end)
    local u2 = store.subscribe(function() calls.b = calls.b + 1 end)
    t:defer(u1); t:defer(u2)
    store.apply_control({ event_id = "x1", type = "task.edited", task = vim.tbl_extend("force", store.tasks["T-002"], { title = "z" }) })
    t:eq(calls.a, 1); t:eq(calls.b, 1, "second subscriber still notified"); t:eq(store.stats.subscriber_errors, 1)
    -- a late finish for an older attempt must not change the current running task
    local running = store.tasks["T-001"]
    local old_finish = vim.tbl_extend("force", running, { state = "succeeded", current_attempt_id = "00000000-0000-4000-8000-000000000999" })
    store.apply_control({ event_id = "late", type = "attempt.finished", attempt_id = "00000000-0000-4000-8000-000000000999", task = old_finish })
    t:eq(store.tasks["T-001"].state, "running", "late record from another attempt ignored")
  end },
  { id = "store.activity_bounded_and_coalesced", tasks = { "SDD-046", "SDD-066" }, suites = { "core" }, run = function(t)
    pl.unload(); require("aiswarm")
    local store = require("aiswarm.store"); store.reset()
    store.LIMITS.activity_records = 100
    t:defer(function() store.LIMITS.activity_records = 2000 end)
    for i = 1, 250 do store.apply_activity({ event_id = "a" .. i, ts = "t", task_id = "T-001", kind = "progress", level = "info", text = "step " .. i }) end
    t:eq(#store.activity.records, 100); t:eq(store.activity.gap, true); t:eq(store.stats.dropped_activity, 150)
    for _ = 1, 5 do store.apply_activity({ event_id = "h" .. vim.uv.hrtime(), ts = "t", task_id = "T-002", kind = "heartbeat", level = "debug", text = "alive", hidden = true }) end
    local last = store.activity.records[#store.activity.records]
    t:eq(last.count, 5, "repeated identical records coalesce with a count")
    t:eq(#store.activity_for({ task_id = "T-002" }), 0, "hidden/debug records excluded by default")
    t:eq(#store.activity_for({ task_id = "T-002", show_hidden = true, min_level = "debug" }), 1, "queryable on demand")
    t:eq(store.stats.subscriber_errors, 0)
  end },
  -- ------------------------------------------------------------ SDD-047
  { id = "viewstate.selection_by_identity", tasks = { "SDD-047" }, suites = { "core" }, run = function(t)
    local V = require("aiswarm.view_state"); V.reset()
    V.select("T-003", nil, 3)
    -- active → finished reorder: the same id moves to another row; selection follows the id
    t:eq(V.reconcile({ "T-001", "T-002", "T-004", "T-003" }), false); t:eq(V.selected.task_id, "T-003"); t:eq(V.selected.index, 4)
    -- filtering removes it: the row now at its former index is chosen
    t:eq(V.reconcile({ "T-001", "T-002", "T-004", "T-005" }), true); t:eq(V.selected.task_id, "T-005")
    V.select("T-005", nil, 4)
    t:eq(V.reconcile({ "T-001", "T-002" }), true); t:eq(V.selected.task_id, "T-002", "previous row when the index no longer exists")
    t:eq(V.reconcile({}), true); t:eq(V.selected.task_id, nil, "empty state")
    -- pinned inspector does not follow the cursor
    V.select("T-001", nil, 1); V.set_tab("output"); t:ok(V.pin())
    V.select("T-002", nil, 2)
    local tid, _, tab = V.target(); t:eq(tid, "T-001"); t:eq(tab, "output")
    V.pin(); tid = V.target(); t:eq(tid, "T-002", "unpin re-syncs to the cursor")
  end },
  -- ------------------------------------------------------------ SDD-048
  { id = "render.burst_is_coalesced_and_hidden_skipped", tasks = { "SDD-048" }, suites = { "core", "performance" }, run = function(t)
    local R = require("aiswarm.ui.render"); R.reset()
    local renders, visible = 0, true
    R.register("v", { render = function() renders = renders + 1 end, visible = function() return visible end })
    for _ = 1, 500 do R.mark("v") end
    t:wait(1000, function() return renders >= 1 end)
    vim.wait(60)
    t:eq(renders, 1, "500 marks → one render"); t:ok(R.stats.batches <= 2)
    visible = false
    for _ = 1, 50 do R.mark("v") end
    vim.wait(60)
    t:eq(renders, 1, "hidden view renders nothing"); t:ok(R.stats.skipped_hidden >= 1)
    R.reset()
  end },
  -- ------------------------------------------------------------ SDD-050
  { id = "text.cells_truncation_and_sanitize", tasks = { "SDD-050" }, suites = { "core" }, run = function(t)
    pl.unload(); require("aiswarm")
    local T = require("aiswarm.ui.text")
    t:eq(T.width("日本語"), 6); t:eq(T.width("🚀"), 2); t:eq(T.width("e\204\129"), 1)
    t:eq(T.truncate("日本語テスト", 7), "日本語…"); t:eq(T.width(T.fit("🚀 go", 10)), 10); t:eq(T.width(T.fit("日本語テスト", 5)), 5)
    t:eq(T.fit("ab", 4, true), "  ab")
    local dirty = "\27]0;evil\7\27[2J\27[31mred\27[0m\27]52;c;ZXZpbA==\7 plain\r\n\1\127"
    t:eq(T.sanitize(dirty), "red plain\n")
    local line = T.line():add("日本", "A"):add(" ", nil):add("🚀", "B")
    local text, spans = line:build()
    t:eq(spans[1], { 0, 6, "A" }); t:eq(spans[2], { 7, 11, "B" }, "byte-accurate spans for multibyte text")
    local buf = vim.api.nvim_create_buf(false, true)
    local ns = vim.api.nvim_create_namespace("aiswarm-test")
    T.set_lines(buf, ns, { { text, spans }, { "x", {} } })
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    t:eq(#marks, 2); t:eq(marks[2][4].end_col, 11)
    t:eq(T.ICONS.ascii.running, "*", "ASCII icons need no Nerd Font")
  end },
  { id = "highlights.theme_defaults_preserve_user_overrides", tasks = { "SDD-050" }, suites = { "core" }, run = function(t)
    local H = require("aiswarm.ui.highlights")
    vim.api.nvim_set_hl(0, "AISwarmFailed", { fg = "#ff0000" })
    H.setup()
    vim.cmd("doautocmd ColorScheme")
    local hl = vim.api.nvim_get_hl(0, { name = "AISwarmFailed" })
    t:eq(hl.fg, 0xff0000, "explicit user definition survives ColorScheme reload")
    local linked = vim.api.nvim_get_hl(0, { name = "AISwarmDone" })
    t:eq(linked.link, "DiagnosticOk")
  end },
}
