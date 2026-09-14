-- SDD-054 cancellable reads, SDD-055 overview, SDD-056 output, SDD-057 report, SDD-058 files, SDD-059 attempts.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local v3 = require("helpers.v3")
local ui = require("helpers.ui")
local function need_snacks(t) if not pcall(require, "snacks") then t:skip("snacks.nvim not available") end end
local function store() return require("aiswarm.store") end
local function V() return require("aiswarm.view_state") end
local function I() return require("aiswarm.ui.inspector") end

--- A v3 board with two tasks whose attempts point at controlled artifact files. The workspace is
--- opened first and backend refreshes are disabled so the fixture state stays authoritative.
local function fixture_board(t, opts)
  opts = opts or {}
  ui.screen(140, 45)
  local root, A = ui.board_with_tasks(t, 2, { name = opts.name or "insp" })
  A.refresh = function(cb) if cb then cb(nil, "fixture-backed") end end
  local ws = ui.open(t)
  local dir = t:tmpdir("artifacts")
  local seq = 0
  local function attempt(id, n, state, extra)
    seq = seq + 1
    local aid = ("00000000-0000-4000-8000-%012d"):format(seq)
    local adir = dir .. "/" .. aid; vim.fn.mkdir(adir, "p")
    local a = { attempt_id = aid, task_id = id, ordinal = n, provider = "mock", state = state, started_at = "2026-09-14T00:00:00Z",
      finished_at = state ~= "running" and "2026-09-14T00:05:00Z" or nil, config = { cwd = dir, timeout = 1800, isolation = "shared", isolation_info = { mode = "shared", path = dir } },
      paths = { dir = adir, stdout = adir .. "/stdout.log", stderr = adir .. "/stderr.log", report = adir .. "/report.md", activity = adir .. "/activity.json" },
      report = { status = extra and extra.report or "missing" } }
    for k, v in pairs(extra or {}) do if k ~= "report" then a[k] = v end end
    return a, adir
  end
  local S = store()
  local snap = { tasks = {}, attempts = {}, scheduler = { state = "running", wip = 3 }, capabilities = { attempts = true, cancel = true, retry = true, telemetry = true }, board = { schema = "v3", board_id = "57fc3ea0-6b8f-45c2-8e8f-3a5f98cc4ed3" } }
  local t1 = vim.deepcopy(S.task("T-001")); local t2 = vim.deepcopy(S.task("T-002"))
  local a1, d1 = attempt("T-001", 1, "running"); local a2, d2 = attempt("T-002", 1, "succeeded", { report = "complete" })
  t1.state, t1.current_attempt_id, t1.attempts, t1.display = "running", a1.attempt_id, { a1.attempt_id }, "Running"
  t2.state, t2.current_attempt_id, t2.attempts, t2.display, t2.outcome = "succeeded", a2.attempt_id, { a2.attempt_id }, "Succeeded", { exit_code = 0, finished_at = "2026-09-14T00:05:00Z", report = "complete" }
  snap.tasks, snap.attempts = { t1, t2 }, { a1, a2 }
  S.apply_snapshot(snap)
  sb.write(a1.paths.stdout, "A line 1\nA line 2\n"); sb.write(a2.paths.stdout, "B line 1\nB line 2\nB line 3\n")
  sb.write(a2.paths.report, "## Summary\nB done\n\n## Files changed\nsrc/b.lua\n- lib/util.lua\n\n## Decisions\n(none)\n\n## Verification\ntests passed (agent claim)\n\n## Follow-ups\n(none)\n")
  sb.write(dir .. "/src/b.lua", "return 1\n")
  ui.flush()
  return root, A, { a1 = a1, a2 = a2, dir = dir, d1 = d1, d2 = d2, ws = ws }
end

return {
  -- ------------------------------------------------------------ SDD-054
  { id = "inspector.delayed_read_only_current_selection_renders", tasks = { "SDD-054" }, suites = { "core" }, run = function(t)
    need_snacks(t)
    local root, A, fx = fixture_board(t)
    local ws = fx.ws
    local loader = require("aiswarm.ui.loader")
    local orig = loader.read
    loader.read = function(path, opts, cb)  -- A's output arrives late
      if path:find(fx.a1.attempt_id, 1, true) then opts = vim.tbl_extend("force", opts, { delay_ms = 300 }) end
      return orig(path, opts, cb)
    end
    t:defer(function() loader.read = orig end)
    local ticks = 0
    local timer = vim.uv.new_timer(); timer:start(5, 5, function() ticks = ticks + 1 end); t:defer(function() timer:stop(); timer:close() end)
    ws.inspect("T-001", nil, "output"); ui.flush()       -- A: slow
    ws.inspect("T-002", nil, "output"); ui.flush()       -- B: fast
    t:wait(2000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("B line 3", 1, true) ~= nil end, "B renders")
    vim.wait(500); ui.flush()
    local text = ui.text(ws.buf("inspector"))
    t:ok(text:find("B line 3", 1, true) and not text:find("A line 1", 1, true), "only B is shown after A's late read")
    t:ok(loader.stats.stale >= 1, "the stale read was discarded: " .. loader.stats.stale)
    t:ok(ticks >= 50, "UI sentinel kept ticking during the slow read: " .. ticks)
    -- zero output vs failed read
    sb.write(fx.a1.paths.stdout, "")
    ws.inspect("T-001", nil, "output"); loader.reset(); I().release(); ui.flush()
    t:wait(2000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("zero bytes", 1, true) ~= nil end, "empty output labelled")
    vim.fn.delete(fx.a1.paths.stdout); vim.fn.mkdir(fx.a1.paths.stdout, "p")   -- a directory: read fails
    loader.reset(); I().release(); ui.flush()
    t:wait(2000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("read failed", 1, true) ~= nil end, "failed read labelled distinctly")
    t:eq(V().selected.task_id, "T-001", "selection preserved through errors")
  end },
  -- ------------------------------------------------------------ SDD-055
  { id = "inspector.overview_labels_are_honest", tasks = { "SDD-055" }, suites = { "core" }, run = function(t)
    need_snacks(t)
    local root, A, fx = fixture_board(t, { name = "ov" })
    local ws = fx.ws
    local S = store()
    local function overview(task_id, patch)
      local task = vim.deepcopy(S.task(task_id)); for k, v in pairs(patch or {}) do task[k] = v end
      S.apply_control({ event_id = "ov" .. vim.uv.hrtime(), type = "task.edited", task = task })
      ws.inspect(task_id, nil, "overview"); ui.flush()
      return ui.text(ws.buf("inspector"))
    end
    local quiet = overview("T-001", { display = "Quiet", display_detail = "no output for 90s", health = { quiet = true, quiet_for_s = 90, heartbeat_at = "2026-09-14T00:00:00Z" } })
    t:match(quiet, "Quiet"); t:match(quiet, "no output for 90s")
    local stale = overview("T-001", { display = "Telemetry stale", display_detail = "no heartbeat for 20s", health = { stale = true, stale_for_s = 20 } })
    t:match(stale, "Telemetry stale"); t:match(stale, "Heartbeat%s+none yet %(telemetry stale")
    local phased = overview("T-001", { display = "Running", display_detail = "testing", health = { message = "Running focused tests", phase = "testing", provenance = "worker_report", activity_at = "2026-09-14T00:01:00Z" } })
    t:match(phased, "Running focused tests %[testing%] · reported by worker_report")
    t:ok(not phased:find("%%"), "no invented percentage")
    local orphan = overview("T-001", { state = "failed", display = "Failed: orphaned", outcome = { reason = "orphaned", finished_at = "2026-09-14T00:02:00Z", report = "missing" } })
    t:match(orphan, "Execution%s+failed · orphaned"); t:match(orphan, "Report%s+not available"); t:match(orphan, "Cost%s+unknown %(not reported%)")
    local done = overview("T-002")
    t:match(done, "Report%s+complete"); t:match(done, "Verification%s+reported by the agent in its report — not independently verified")
    t:match(done, "Isolation%s+shared")
  end },
  -- ------------------------------------------------------------ SDD-056
  { id = "inspector.output_bounded_follow_and_transcript", tasks = { "SDD-056" }, suites = { "core", "performance" }, run = function(t)
    need_snacks(t)
    local root, A, fx = fixture_board(t, { name = "out" })
    local ws = fx.ws
    local big = {}
    for i = 1, 30000 do big[i] = ("line %06d %s"):format(i, ("x"):rep(80)) end
    sb.write(fx.a1.paths.stdout, table.concat(big, "\n") .. "\n")
    ws.inspect("T-001", nil, "output")
    t:wait(5000, function() ui.flush(); return I().current.entry and I().current.entry.status == "content" end, "flood loaded")
    local entry = I().current.entry
    t:ok(#entry.lines <= I().LIMITS.output_lines, "line bound: " .. #entry.lines); t:eq(entry.truncated, true)
    t:ok(vim.api.nvim_buf_line_count(ws.buf("inspector")) <= I().LIMITS.output_lines + 10)
    t:match(ui.lines(ws.buf("inspector"), 4, 5)[1], "showing the last part")
    -- scrolling pauses following and counts unread; f and G resume
    ws.focus("inspector"); local iwin = ws.win_of("inspector")
    t:eq(V().output.follow, true)
    vim.api.nvim_win_set_cursor(iwin, { 10, 0 }); vim.api.nvim_exec_autocmds("CursorMoved", { buffer = ws.buf("inspector") }); ui.flush()
    t:eq(V().output.follow, false)
    sb.write(fx.a1.paths.stdout, table.concat(big, "\n") .. "\nNEW 1\nNEW 2\n")
    require("aiswarm.ui.loader").reset(); I().release(); ui.flush()
    t:wait(5000, function() ui.flush(); return V().output.unread > 0 end, "unread counted while paused")
    t:eq(vim.api.nvim_win_get_cursor(iwin)[1], 10, "cursor stayed put")
    ui.keys("f"); t:eq(V().output.follow, true); t:eq(V().output.unread, 0)
    t:eq(vim.api.nvim_win_get_cursor(iwin)[1], vim.api.nvim_buf_line_count(ws.buf("inspector")), "following jumps to the end")
    -- switching attempts cannot mix bytes
    ws.inspect("T-002", nil, "output"); t:wait(3000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("B line 1", 1, true) ~= nil end)
    t:ok(not ui.text(ws.buf("inspector")):find("line 000001", 1, true), "no bytes from the other attempt")
    -- stderr stream toggle and full transcript action
    ui.keys("s"); ui.flush(); t:match(ui.lines(ws.buf("inspector"), 4, 5)[1], "Output · stderr"); ui.keys("s")
    local actions = require("aiswarm.ui.actions")
    actions.run("transcript", actions.target("T-002"))
    t:eq(vim.api.nvim_buf_get_name(0), fx.a2.paths.stdout, "full transcript opens the exact artifact"); t:eq(ws.is_open(), false)
  end },
  -- ------------------------------------------------------------ SDD-057
  { id = "inspector.report_bound_to_attempt", tasks = { "SDD-057" }, suites = { "core" }, run = function(t)
    need_snacks(t)
    local root, A, fx = fixture_board(t, { name = "rep" })
    local ws = fx.ws
    local S = store()
    -- a retry: attempt 2 of T-002 with no report; attempt 1 keeps its report
    local a3 = vim.deepcopy(fx.a2); a3.attempt_id = "00000000-0000-4000-8000-000000000003"; a3.ordinal = 2; a3.report = { status = "missing" }
    local d3 = fx.dir .. "/" .. a3.attempt_id; vim.fn.mkdir(d3, "p"); a3.paths = { dir = d3, stdout = d3 .. "/stdout.log", stderr = d3 .. "/stderr.log", report = d3 .. "/report.md" }
    local t2 = vim.deepcopy(S.task("T-002")); t2.current_attempt_id = a3.attempt_id; t2.attempts = { fx.a2.attempt_id, a3.attempt_id }; t2.outcome.report = "missing"
    S.apply_control({ event_id = "r1", type = "attempt.finished", task = t2, attempt = a3 })
    ws.inspect("T-002", nil, "report"); ui.flush()
    t:wait(3000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("No report for this attempt", 1, true) ~= nil end, "missing, not the predecessor's text")
    t:ok(not ui.text(ws.buf("inspector")):find("B done", 1, true))
    -- historical attempt intentionally opens its own report
    ws.inspect("T-002", fx.a2.attempt_id, "report"); ui.flush()
    t:wait(3000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("B done", 1, true) ~= nil end, "attempt 1's report")
    t:match(ui.text(ws.buf("inspector")), "Report · attempt 1 · complete")
    -- results picker items carry task/attempt identity
    local items = require("aiswarm.ui.results").items()
    t:eq(#items, 1); t:eq(items[1].id, "T-002"); t:match(items[1].label, "attempt 1")
    -- read error preserves selection
    vim.fn.delete(fx.a2.paths.report); vim.fn.mkdir(fx.a2.paths.report, "p")
    require("aiswarm.ui.loader").reset(); I().release(); ui.flush()
    t:wait(3000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("read failed", 1, true) ~= nil end)
    t:eq(V().selected.task_id, "T-002"); t:ok(ws.is_open())
  end },
  -- ------------------------------------------------------------ SDD-058
  { id = "inspector.files_with_provenance", tasks = { "SDD-058" }, suites = { "core" }, run = function(t)
    need_snacks(t)
    local root, A, fx = fixture_board(t, { name = "files" })
    local ws = fx.ws
    ws.inspect("T-002", nil, "report"); t:wait(3000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("B done", 1, true) ~= nil end)
    ws.inspect("T-002", nil, "files"); ui.flush()
    local text = ui.text(ws.buf("inspector"))
    t:match(text, "src/b%.lua%s+report %(agent%-written%)"); t:match(text, "lib/util%.lua"); t:match(text, "shared working directory: changes cannot be attributed")
    ws.focus("inspector"); local iwin = ws.win_of("inspector")
    local row; for i, r in pairs(I().rows) do if r.file and r.file.path == "src/b.lua" then row = i end end
    vim.api.nvim_win_set_cursor(iwin, { row, 0 })
    ui.keys("<CR>")
    t:eq(vim.api.nvim_buf_get_name(0), fx.dir .. "/src/b.lua", "opens the path resolved against the attempt cwd")
    -- missing file: recovery message, no crash
    local ws2 = ui.open(t); ws2.inspect("T-002", nil, "files"); ui.flush(); ws2.focus("inspector")
    for i, r in pairs(I().rows) do if r.file and r.file.path == "lib/util.lua" then row = i end end
    vim.api.nvim_win_set_cursor(ws2.win_of("inspector"), { row, 0 })
    local seen = pl.capture_notify(function() ui.keys("<CR>") end)
    t:match(seen[1].msg, "file not found"); t:ok(ws2.is_open())
    local seen2 = pl.capture_notify(function() ui.keys("d") end)
    t:ok(#seen2 == 0 or seen2[1].msg:match("diff"), "missing diff dependency yields a message")
  end },
  -- ------------------------------------------------------------ SDD-059
  { id = "inspector.attempt_history_navigation", tasks = { "SDD-059" }, suites = { "core" }, run = function(t)
    need_snacks(t)
    local root, A, fx = fixture_board(t, { name = "att" })
    local ws = fx.ws
    local S = store()
    local a3 = vim.deepcopy(fx.a2); a3.attempt_id = "00000000-0000-4000-8000-000000000003"; a3.ordinal = 2; a3.state = "cancelled"; a3.reason = "cancelled"; a3.report = { status = "missing" }
    local d3 = fx.dir .. "/" .. a3.attempt_id; vim.fn.mkdir(d3, "p"); a3.paths = { dir = d3, stdout = d3 .. "/stdout.log", stderr = d3 .. "/stderr.log", report = d3 .. "/report.md" }
    sb.write(a3.paths.stdout, "C line 1\n")
    local imported = vim.deepcopy(a3); imported.attempt_id = "00000000-0000-4000-8000-000000000004"; imported.ordinal = 3; imported.state = "failed"; imported.imported = { legacy = true }; imported.paths.stdout = d3 .. "/legacy.log"
    local t2 = vim.deepcopy(S.task("T-002")); t2.state = "cancelled"; t2.display = "Cancelled"; t2.current_attempt_id = a3.attempt_id; t2.attempts = { fx.a2.attempt_id, a3.attempt_id, imported.attempt_id }
    S.apply_control({ event_id = "x1", type = "task.cancelled", task = t2, attempt = a3 })
    S.apply_control({ event_id = "x2", type = "task.imported", attempt = imported })
    ws.inspect("T-002", nil, "attempts"); ui.flush()
    local text = ui.text(ws.buf("inspector"))
    t:match(text, "#1%s+mock%s+succeeded"); t:match(text, "#2%s+mock%s+cancelled"); t:match(text, "#3.*failed.*imported")
    ws.focus("inspector"); local iwin = ws.win_of("inspector")
    local row; for i, r in pairs(I().rows) do if r.attempt_id == fx.a2.attempt_id then row = i end end
    vim.api.nvim_win_set_cursor(iwin, { row, 0 }); ui.keys("<CR>")
    local _, aid = V().target(); t:eq(aid, fx.a2.attempt_id)
    ws.inspect("T-002", fx.a2.attempt_id, "output"); t:wait(3000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("B line 1", 1, true) ~= nil end, "output follows the selected attempt")
    ws.inspect("T-002", fx.a2.attempt_id, "report"); t:wait(3000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("B done", 1, true) ~= nil end, "report follows the selected attempt")
    -- pin, then a new attempt arrives: the pinned historical selection stays
    ui.keys("p"); t:ok(V().pinned)
    local a5 = vim.deepcopy(a3); a5.attempt_id = "00000000-0000-4000-8000-000000000005"; a5.ordinal = 4; a5.state = "running"
    local t2b = vim.deepcopy(S.task("T-002")); t2b.state = "running"; t2b.current_attempt_id = a5.attempt_id; table.insert(t2b.attempts, a5.attempt_id)
    S.apply_control({ event_id = "x3", type = "attempt.started", task = t2b, attempt = a5 }); ui.flush()
    local tid, aid2, tab = V().target(); t:eq(aid2, fx.a2.attempt_id, "pinned historical attempt not overwritten"); t:eq(tab, "report")
  end },
}
