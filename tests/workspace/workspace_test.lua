-- SDD-049 shell, SDD-051 task list, SDD-052 actions, SDD-053 layout, SDD-060 picker, SDD-065 first use, SDD-066 activity, SDD-067 notifications.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local v3 = require("helpers.v3")
local ui = require("helpers.ui")
local fx = require("fixtures.state.mixed_snapshot")
local function need_snacks(t) if not pcall(require, "snacks") then t:skip("snacks.nvim not available") end end
local function store() return require("aiswarm.store") end
local function V() return require("aiswarm.view_state") end

return {
  -- ------------------------------------------------------------ SDD-049
  { id = "workspace.single_instance_and_release_only_views", tasks = { "SDD-049" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root, A = ui.board_with_tasks(t, 3)
    local editor_win = vim.api.nvim_get_current_win()
    local ws = ui.open(t)
    local layout = ws.layout
    ws.open({}); ui.flush()
    t:ok(ws.layout == layout, "repeated open focuses the existing workspace"); t:eq(ws.stats.opens, 1)
    t:eq(vim.tbl_count(vim.tbl_filter(function(b) return vim.api.nvim_buf_get_name(b):match("^aiswarm://tasks") end, vim.api.nvim_list_bufs())), 1)
    ui.keys("<Tab>"); t:ok(ws.is_open(), "pane action does not close the workspace"); t:eq(ws.focus_name(), "inspector")
    ui.keys("<Tab>"); t:eq(ws.focus_name(), "activity"); ui.keys("<S-Tab>"); t:eq(ws.focus_name(), "inspector")
    local S = A.state()
    ui.keys("q")
    t:eq(ws.is_open(), false); t:eq(vim.api.nvim_get_current_win(), editor_win, "q returns editor focus")
    t:eq(S._stopped, false, "closing the workspace keeps the session (and any scheduler/workers) running")
    t:eq(require("aiswarm.ui.render").views.tasks, nil, "view resources released")
    t:eq(#store()._subs >= 1, true, "store keeps its non-view subscribers (notifications)")
  end },
  { id = "workspace.docked_layout_preserves_editing_windows", tasks = { "SDD-049" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root, A = ui.board_with_tasks(t, 2, { setup = { ui = { layout = "editor" } } })
    local buf = vim.api.nvim_create_buf(true, false); vim.api.nvim_set_current_buf(buf); vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "editing" })
    local editor_win = vim.api.nvim_get_current_win()
    local ws = ui.open(t)
    t:ok(vim.api.nvim_win_is_valid(editor_win), "normal editing window still exists")
    t:eq(vim.api.nvim_win_get_buf(editor_win), buf, "editing window keeps its buffer")
    t:ok(ws.layout.split == true, "docked mode is a split layout, not a float")
    t:ok(ws.mode ~= nil, "docked mode resolved a layout: " .. tostring(ws.mode))
    ws.close()
    t:eq(vim.api.nvim_get_current_win(), editor_win)
  end },
  -- ------------------------------------------------------------ SDD-051
  { id = "tasks.grouped_thousand_fixture", tasks = { "SDD-051" }, suites = { "core", "performance" }, run = function(t)
    pl.unload(); require("aiswarm")
    local S = store(); S.reset(); local Vs = V(); Vs.reset()
    S.apply_snapshot(fx.snapshot(1000))
    local c = S.counts()
    t:eq(c.all, 1000); t:eq(c.running, 167); t:eq(c.queued, 333); t:eq(c.attention, 167); t:eq(c.finished, 333); t:eq(c.blocked, 166)
    local started = vim.uv.hrtime()
    local lines, rowmap, visible = require("aiswarm.ui.tasks").build(S, Vs, { width = 60 })
    local ms = (vim.uv.hrtime() - started) / 1e6
    t:ok(ms < 500, "1,000-task render under 500 ms: " .. ms)
    t:eq(#visible, 1000)
    local g = S.grouped()
    for i = 2, #g.groups.queued do t:ok(require("aiswarm.protocol").compare_queue(g.groups.queued[i - 1], g.groups.queued[i]) or g.groups.queued[i - 1].priority == g.groups.queued[i].priority, "numeric queue order") end
    for i = 2, #g.groups.finished do t:ok((g.groups.finished[i - 1].outcome.finished_at) >= (g.groups.finished[i].outcome.finished_at), "finished newest first") end
    t:eq(S.grouped({ text = "🚀" }).shown, 250); t:eq(S.grouped({ group = "attention" }).shown, 167)
    -- blocked and failed rows carry readable text
    local text = table.concat(vim.tbl_map(function(l) return l[1] end, lines), "\n")
    t:ok(text:find("waiting for T%-005 %(cancelled%)") or text:find("blocked by"), "blocked reason visible as text")
    t:ok(text:find("Failed") and text:find("exit 1"), "failure state as text")
    -- collapsing keeps a valid selected id
    Vs.select("T-004", nil, 1)
    Vs.toggle_group("attention")
    local _, _, vis2 = require("aiswarm.ui.tasks").build(S, Vs, { width = 60 })
    t:eq(Vs.reconcile(vis2), true); t:ok(S.task(Vs.selected.task_id) ~= nil, "selection falls back to a visible task")
  end },
  { id = "tasks.live_status_change_keeps_selection", tasks = { "SDD-051", "SDD-047" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root, A = ui.board_with_tasks(t, 3)
    local ws = ui.open(t)
    -- select T-002 (second row), then T-001 finishes: order changes but selection stays T-002
    local row = require("aiswarm.ui.tasks").row_of(ws.rowmap, "T-002")
    vim.api.nvim_win_set_cursor(ws.win_of("tasks"), { row, 0 }); ws.on_cursor(); ui.flush()
    t:eq(V().selected.task_id, "T-002")
    v3.cli_json(t, root, { "cancel", "T-001" })
    ui.refresh(t, A)
    t:eq(V().selected.task_id, "T-002", "identity kept across reorder")
    local cur = vim.api.nvim_win_get_cursor(ws.win_of("tasks"))[1]
    t:eq(ws.rowmap[cur].task_id, "T-002", "cursor follows the task, not the row number")
  end },
  -- ------------------------------------------------------------ SDD-052
  { id = "actions.conflict_when_state_changes_under_confirmation", tasks = { "SDD-052" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root, A = ui.board_with_tasks(t, 2)
    local ws = ui.open(t)
    local actions = require("aiswarm.ui.actions")
    local target = actions.target("T-001")
    t:eq(target.revision, 1)
    local seen = pl.capture_notify(function()
      actions.run("cancel", target)          -- opens the confirmation naming the task
      t:ok(actions.last_confirm and actions.last_confirm.text:match("Cancel T%-001"), "confirmation names the target")
      -- meanwhile the task changes (edited: revision 2)
      v3.cli_json(t, root, { "set", "T-001", "--expect-revision", "1", "--title", "changed" })
      ui.refresh(t, A)
      ui.keys("y")
      vim.wait(300)
    end)
    local msgs = table.concat(vim.tbl_map(function(n) return n.msg end, seen), "\n")
    t:match(msgs, "Task changed; review current state")
    t:eq(v3.cli_json(t, root, { "snapshot" }).tasks[1].state, "queued", "no cancel hit the changed task")
    t:eq(store().task("T-002").state, "queued", "and not another task either")
  end },
  { id = "actions.taskless_row_cannot_act_and_keys_are_explicit", tasks = { "SDD-052" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root, A = ui.board_with_tasks(t, 2)
    local ws = ui.open(t)
    local twin = ws.win_of("tasks")
    -- cursor on the QUEUED group header
    local hdr
    for i, r in pairs(ws.rowmap) do if r.group and not r.task_id and r.group == "queued" then hdr = i end end
    vim.api.nvim_win_set_cursor(twin, { hdr, 0 })
    local before = V().selected.task_id
    local seen = pl.capture_notify(function() ui.keys("x") end)
    t:ok(ws.is_open(), "workspace stays open")
    t:eq(#vim.tbl_filter(function(n) return n.msg:match("cancel") end, seen), 0, "no cancel executed from a header row (selection unchanged: " .. tostring(before) .. ")")
    ui.keys("<CR>")   -- Enter on a group header toggles it, never closes the board
    t:ok(ws.is_open()); t:eq(V().collapsed.queued, true); ui.keys("<CR>"); t:eq(V().collapsed.queued, false)
    -- Enter on a task inspects; g attaches explicitly (not inside tmux → explicit warning, no session switch)
    local row = require("aiswarm.ui.tasks").row_of(ws.rowmap, "T-001")
    vim.api.nvim_win_set_cursor(twin, { row, 0 }); ws.on_cursor(); ui.flush()
    ui.keys("<CR>"); t:eq(ws.focus_name(), "inspector"); t:ok(ws.is_open(), "Enter inspects without closing")
    vim.env.TMUX = nil
    local seen2 = pl.capture_notify(function() ui.keys("g") end)
    t:ok(#seen2 >= 1 and seen2[1].msg:match("tmux"), "attach is explicit and explains: " .. vim.inspect(seen2))
    -- action menu lists legal actions with reasons for illegal ones
    local list = require("aiswarm.ui.actions").list(require("aiswarm.ui.actions").target("T-001"))
    local by = {}; for _, it in ipairs(list) do by[it.name] = it end
    t:eq(by.retry.legal, false); t:match(by.retry.reason, "finished"); t:eq(by.cancel.legal, true); t:eq(by.edit.legal, true)
  end },
  { id = "actions.commands_resolve_context_or_picker", tasks = { "SDD-052", "SDD-012" }, suites = { "core" }, isolated = true, run = function(t)
    need_snacks(t); ui.screen(80, 24)
    local root, A = ui.board_with_tasks(t, 2)
    pl.source_plugin()
    local ws = ui.open(t)
    V().select("T-002", nil, 2)
    vim.cmd("AISwarm inspect"); ui.flush()
    t:eq(select(1, V().target()), "T-002", "omitted id resolves to the workspace selection")
    vim.cmd("AISwarm report T-001"); ui.flush()
    local tid, _, tab = V().target(); t:eq(tid, "T-001"); t:eq(tab, "report")
    local seen = pl.capture_notify(function() vim.cmd("AISwarm inspect NOPE") end)
    t:match(seen[1].msg, "no such task")
    ws.close()
    -- without a workspace a picker opens for the omitted id
    vim.cmd("AISwarm output"); vim.wait(100)
    local picker = require("aiswarm.ui.picker").current
    t:ok(picker ~= nil and not picker.closed, "picker opened to resolve the target"); picker:close()
  end },
  -- ------------------------------------------------------------ SDD-053
  { id = "layout.resolver_is_total_and_matches_adr", tasks = { "SDD-053", "SDD-007" }, suites = { "core" }, run = function(t)
    local L = require("aiswarm.ui.layout")
    local seen = {}
    for w = 1, 200 do for h = 1, 100 do
      local m = L.resolve(w, h); t:ok(m == "wide" or m == "medium" or m == "narrow" or m == "minimal", ("valid mode at %dx%d"):format(w, h)); seen[m] = true
      local g = L.geometry(m, w, h)
      for k, v in pairs(g) do t:ok(v >= 1 or k == "tray", ("no invalid dimension %s=%s at %dx%d"):format(k, tostring(v), w, h)) end
    end end
    t:eq(L.resolve(110, 28), "wide"); t:eq(L.resolve(110, 27), "medium"); t:eq(L.resolve(109, 28), "medium"); t:eq(L.resolve(80, 24), "medium")
    t:eq(L.resolve(79, 24), "narrow"); t:eq(L.resolve(80, 23), "narrow"); t:eq(L.resolve(40, 12), "narrow"); t:eq(L.resolve(39, 12), "minimal"); t:eq(L.resolve(40, 11), "minimal")
    t:ok(seen.wide and seen.medium and seen.narrow and seen.minimal)
  end },
  { id = "layout.resize_preserves_navigation_state", tasks = { "SDD-053" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root, A = ui.board_with_tasks(t, 4)
    local ws = ui.open(t)
    t:eq(ws.mode, "wide")
    V().select("T-003", nil, 3); V().set_filter("task"); V().set_tab("output"); V().output.wrap = true
    ws.render_all(); ui.flush()
    ws.focus("inspector")
    -- 35x10 (minimal) is covered by the pure resolver test and the real-terminal SDD-098 evidence: this
    -- development build of Neovim aborts when floats are drawn on a headless grid that small.
    -- expected modes follow the interior (terminal minus border, cmdline and statusline): 100x30 → 98x26 medium,
    -- 80x24 → 78x20 narrow, 60x20 narrow, 42x14 → 40x10 minimal, 112x32 → 110x28 wide, 112x31 medium, 111x32 medium.
    local sizes = { { 100, 30, "medium" }, { 80, 24, "narrow" }, { 60, 20, "narrow" }, { 42, 14, "minimal" }, { 112, 32, "wide" }, { 112, 31, "medium" }, { 111, 32, "medium" }, { 140, 45, "wide" } }
    for _, s in ipairs(sizes) do
      ui.screen(s[1], s[2]); ws.relayout(); ui.flush()
      t:eq(ws.mode, s[3], ("mode at %dx%d"):format(s[1], s[2]))
      for name, win in pairs(ws.wins) do
        t:ok(win:valid(), name .. " valid at " .. s[1] .. "x" .. s[2])
        t:ok(vim.api.nvim_win_get_width(win.win) >= 1 and vim.api.nvim_win_get_height(win.win) >= 1, "no invalid dimensions")
      end
      t:eq(V().selected.task_id, "T-003", "selection survives " .. s[3]); t:eq(V().filter.text, "task"); t:eq(V().tab, "output"); t:eq(V().output.wrap, true)
      if s[3] ~= "minimal" then t:eq(ws.focus_name(), "inspector", "focus kept in " .. s[3]) end
      local cur = vim.api.nvim_get_current_win()
      t:ok(cur == (ws.win_of("inspector") or ws.win_of("tasks")), "focus not stolen by another window")
    end
    -- narrow: Backspace returns to tasks with selection intact; Enter navigates in
    ui.screen(60, 20); ws.relayout(); ui.flush()
    ui.keys("<BS>"); t:eq(ws.focus_name(), "tasks"); t:eq(V().selected.task_id, "T-003")
    ui.keys("<CR>"); t:eq(ws.focus_name(), "inspector")
  end },
  -- ------------------------------------------------------------ SDD-060
  { id = "picker.live_updates_keep_query", tasks = { "SDD-060" }, suites = { "core" }, isolated = true, run = function(t)
    need_snacks(t); ui.screen(80, 24)
    local root, A = ui.board_with_tasks(t, 3)
    local subs_before = #store()._subs
    local picker = require("aiswarm.ui.picker").pick()
    t:defer(function() if not picker.closed then picker:close() end end)
    vim.wait(200)
    picker.input:set("task 2")
    picker:find(); vim.wait(300)
    t:eq(picker.input:get(), "task 2")
    t:ok(#store()._subs == subs_before + 1, "picker subscribes while open")
    v3.cli_json(t, root, { "set", "T-002", "--expect-revision", "1", "--title", "task 2 renamed" })
    ui.refresh(t, A); vim.wait(400)
    t:eq(picker.input:get(), "task 2", "query preserved across live refresh")
    local found = false
    for _, item in ipairs(picker:items()) do if item.id == "T-002" and store().task("T-002").title == "task 2 renamed" then found = true end end
    t:ok(found, "rows refreshed with the new state")
    picker:close(); vim.wait(50)
    t:eq(#store()._subs, subs_before, "closing unsubscribes")
    -- a stale record is rejected by the shared action layer
    local actions = require("aiswarm.ui.actions")
    local stale = { board_id = store().board.board_id, task_id = "T-002", revision = 1, state = "queued" }
    local seen = pl.capture_notify(function() actions.run("retry", stale) end)
    t:ok(#seen >= 1, vim.inspect(seen))
  end },
  -- ------------------------------------------------------------ SDD-065
  { id = "firstuse.no_board_to_running_scheduler", tasks = { "SDD-065" }, suites = { "core" }, isolated = true, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    t:defer(function() sb.tmux({ "kill-server" }) end)
    local dir = t:tmpdir("first"); sb.run({ "git", "init", "-q", dir }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME } })
    vim.env.AISWARM_ROOT = nil
    pl.unload(); local A = require("aiswarm")
    local cwd = vim.uv.cwd(); vim.cmd.cd(dir); t:defer(function() vim.cmd.cd(cwd) end)
    A.setup({ bin = sb.bin("aiswarm"), follow = false, register_server = false }); t:defer(function() require("aiswarm.project").close() end)
    local ws = ui.open(t)
    t:ok(not sb.exists(dir .. "/.aiswarm"), "opening created nothing")
    local text = ui.text(ws.buf("tasks"))
    t:match(text, "No aiswarm board"); t:match(text, "c   create a board"); t:match(text, "mock%s+available")
    ui.keys("c")
    t:wait(10000, function() return require("aiswarm.project").current ~= nil and require("aiswarm.project").current.schema == "v3" end, "board created from the keyboard")
    ui.refresh(t, A)
    t:ok(sb.exists(dir .. "/.aiswarm/board.json"))
    -- queue a task through the composer (mock is the default provider)
    ui.keys("n"); vim.wait(100)
    local cbuf = vim.api.nvim_get_current_buf()
    t:ok(vim.api.nvim_buf_get_name(cbuf):match("^aiswarm://compose"), "composer opened")
    t:match(ui.lines(cbuf, 1, 2)[1], "Provider:%s+mock")
    vim.api.nvim_buf_set_lines(cbuf, 7, -1, false, { "say hello" })
    require("aiswarm.ui.composer").submit(cbuf)
    t:wait(10000, function() return store().task("T-001") ~= nil end, "task queued")
    ui.flush()
    t:match(ui.text(ws.buf("tasks")), "scheduler stopped: queued tasks wait", "explains why work waits")
    ui.keys("S")
    t:wait(15000, function() return store().scheduler.state == "running" end, "scheduler started from the keyboard")
    ui.flush(); t:ok(not ui.text(ws.buf("tasks")):match("scheduler stopped"))
    -- disconnect keeps cached data with age and a reconnect affordance
    store().set_connection({ state = "offline", error = "backend unreachable" }); ui.flush()
    local banner = ui.lines(ws.buf("tasks"), 0, 1)[1]
    t:match(banner, "offline"); t:match(banner, "cached %d+s ago"); t:match(banner, "Ctrl%-r")
    t:ok(store().task("T-001") ~= nil, "cached tasks retained")
  end },
  -- ------------------------------------------------------------ SDD-066
  { id = "activity.feed_filters_bounds_and_follow", tasks = { "SDD-066" }, suites = { "core", "performance" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root, A = ui.board_with_tasks(t, 2)
    local ws = ui.open(t)
    local S = store()
    S.apply_activity({ event_id = "l1", ts = "2026-09-14T14:32:05Z", task_id = "T-001", kind = "lifecycle", level = "info", text = "started", source = "backend", provenance = "backend" })
    S.apply_activity({ event_id = "p1", ts = "2026-09-14T14:32:06Z", task_id = "T-002", kind = "progress", level = "info", text = "Updated login helper text", source = "worker", provenance = "worker_report" })
    S.apply_activity({ event_id = "h1", ts = "2026-09-14T14:32:07Z", task_id = "T-001", kind = "heartbeat", level = "debug", text = "alive", hidden = true })
    S.apply_activity({ event_id = "o1", ts = "2026-09-14T14:32:07Z", task_id = "T-001", kind = "output", level = "debug", text = "raw line", hidden = true })
    S.apply_activity({ event_id = "e1", ts = "2026-09-14T14:32:08Z", task_id = "T-001", kind = "lifecycle", level = "error", text = "failed: exit 1", source = "backend" })
    ui.flush()
    local text = ui.text(ws.buf("activity"))
    t:match(text, "14:32:05%s+T%-001"); t:match(text, "Updated login helper"); t:ok(not text:find("alive") and not text:find("raw line"), "heartbeat/raw output hidden by default")
    require("aiswarm.ui.activity").toggle_verbose(); ui.flush()
    t:ok(ui.text(ws.buf("activity")):find("alive"), "queryable when verbose"); require("aiswarm.ui.activity").toggle_verbose(); ui.flush()
    -- scroll up: following pauses, new events do not move the cursor
    ws.focus("activity")
    local awin = ws.win_of("activity")
    vim.api.nvim_win_set_cursor(awin, { 2, 0 }); vim.api.nvim_exec_autocmds("CursorMoved", { buffer = ws.buf("activity") }); ui.flush()
    t:eq(V().feed.follow, false)
    for i = 1, 5 do S.apply_activity({ event_id = "n" .. i, ts = "t", task_id = "T-002", kind = "progress", level = "info", text = "step " .. i }) end
    ui.flush()
    t:eq(vim.api.nvim_win_get_cursor(awin)[1], 2, "cursor did not jump"); t:eq(V().feed.unread, 5)
    ui.keys("f"); t:eq(V().feed.follow, true); t:eq(V().feed.unread, 0)
    -- repeated previews coalesce with an honest count; flood stays bounded
    for _ = 1, 4 do S.apply_activity({ event_id = "r" .. vim.uv.hrtime(), ts = "t", task_id = "T-002", kind = "output", level = "info", text = "same preview" }) end
    ui.flush(); t:match(ui.text(ws.buf("activity")), "same preview%s+×4")
    for i = 1, 2500 do S.apply_activity({ event_id = "f" .. i, ts = "t", task_id = "T-001", kind = "progress", level = "info", text = "flood " .. i }) end
    t:ok(#S.activity.records <= S.LIMITS.activity_records); t:ok(S.activity.bytes <= S.LIMITS.activity_bytes)
    ui.flush(); t:match(ui.text(ws.buf("activity")), "older records evicted")
    t:eq(require("aiswarm.ui.render").stats.renders < 60, true, "burst rendering coalesced: " .. require("aiswarm.ui.render").stats.renders)
  end },
  -- ------------------------------------------------------------ SDD-067
  { id = "notify.dedupe_bursts_and_no_storm", tasks = { "SDD-067" }, suites = { "core" }, run = function(t)
    pl.unload(); local A = require("aiswarm")
    A.config.notify = { failed = true, completed = true, input_required = true, progress = false, started = false }
    local N = require("aiswarm.notify"); N.WINDOW_MS = 100
    local S = store(); S.reset(); N.attach(); t:defer(function() N.detach() end)
    local snap = fx.snapshot(4)
    local toasts = pl.capture_notify(function()
      S.apply_snapshot(snap)  -- history at attach: no toasts
      vim.wait(200)
    end)
    t:eq(#toasts, 0, "reconnect/attach history produces no toast")
    toasts = pl.capture_notify(function()
      local done = vim.tbl_extend("force", snap.tasks[2], { state = "succeeded", outcome = { finished_at = "2026-09-14T02:00:00Z", exit_code = 0 } })
      S.apply_control({ event_id = "push:1", type = "task.finished", task = done, ids = { "T-002" } })
      S.apply_control({ event_id = "stream:1", type = "task.finished", task = done, ids = { "T-002" } }) -- same completion via another channel
      local orphan = vim.tbl_extend("force", snap.tasks[1], { state = "failed", outcome = { finished_at = "2026-09-14T02:00:01Z", reason = "orphaned" } })
      S.apply_control({ event_id = "s:2", type = "task.finished", task = orphan, ids = { "T-001" } })
      for i = 1, 200 do S.apply_activity({ event_id = "prog" .. i, ts = "t", task_id = "T-003", kind = "progress", level = "info", text = "p" .. i }) end
      vim.wait(300)
    end)
    t:eq(#toasts, 1, "one aggregated toast for the burst: " .. vim.inspect(vim.tbl_map(function(x) return x.msg end, toasts)))
    t:match(toasts[1].msg, "✓ T%-002"); t:match(toasts[1].msg, "✗ T%-001 orphaned")
    t:eq(N.stats.toasts, 1, "no second toast for the duplicate completion"); t:eq(#N.pending, 0, "nothing left to toast: " .. vim.inspect(N.pending))
    t:ok(S.attention["T-001"] and not S.attention["T-001"].acknowledged, "attention persists until viewed")
    local before = S.unacknowledged(); S.acknowledge("T-001"); t:eq(S.unacknowledged(), before - 1, "viewing acknowledges only that task")
  end },
}
