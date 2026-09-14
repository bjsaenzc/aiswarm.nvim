-- SDD-061 composer, SDD-062 advanced validation, SDD-063 drafts, SDD-064 submit/edit, SDD-068 keyboard journeys.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local v3 = require("helpers.v3")
local ui = require("helpers.ui")
local function need_snacks(t) if not pcall(require, "snacks") then t:skip("snacks.nvim not available") end end
local function store() return require("aiswarm.store") end
local function V() return require("aiswarm.view_state") end
local function C() return require("aiswarm.ui.composer") end
local function current_composer()
  for buf, st in pairs(C().open_bufs) do if vim.api.nvim_buf_is_valid(buf) then return buf, st end end
end
local function kill_server(t) t:defer(function() sb.tmux({ "kill-server" }) end) end

return {
  -- ------------------------------------------------------------ SDD-061
  { id = "composer.prompt_first_and_provider_default", tasks = { "SDD-061" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root, A = ui.board_with_tasks(t, 1)
    vim.env.AISWARM_PROVIDER, vim.env.HIVE_PROVIDER = nil, nil
    local buf = C().open({ fresh = true })
    t:defer(function() local _, st = current_composer(); if st and st.win and st.win:valid() then st.closed = true; st.win:close() end end)
    local lines = ui.lines(buf)
    t:match(lines[2], "^Provider:%s+mock$", "default matches the CLI/registry default")
    t:eq(vim.api.nvim_win_get_cursor(0)[1], 8, "cursor starts in the prompt (insert mode is requested for immediate typing)")
    vim.cmd("stopinsert")
    -- unavailable provider cannot be submitted
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "Provider:     claude" })
    vim.api.nvim_buf_set_lines(buf, 7, -1, false, { "do it" })
    local seen = pl.capture_notify(function() C().submit(buf); vim.wait(200) end)
    t:match(seen[1].msg, "Provider: claude is unavailable")
    t:eq(#vim.diagnostic.get(buf), 1); t:eq(vim.diagnostic.get(buf)[1].lnum, 1, "error placed on the Provider line")
    t:eq(store().task("T-002"), nil, "nothing submitted")
    -- source selection with blank lines and header-like lines stays intact
    local _, st = current_composer(); st.closed = true; st.win:close()
    local buf2 = C().open({ prefill = { "first", "", "Title: not a field", "#: literal", "last" }, source = { path = "/x/y.lua", line1 = 3, line2 = 7 } })
    local _, prompt = C().parse(ui.lines(buf2))
    t:eq(prompt, { "first", "", "Title: not a field", "#: literal", "last" })
    local _, st2 = current_composer(); st2.closed = true; st2.win:close()
  end },
  -- ------------------------------------------------------------ SDD-062
  { id = "composer.advanced_validation_identifies_fields", tasks = { "SDD-062" }, suites = { "core" }, run = function(t)
    pl.unload(); require("aiswarm")
    local S = store(); S.reset()
    S.apply_snapshot(require("fixtures.state.mixed_snapshot").snapshot(3))
    vim.env.AISWARM_WORKTREES = nil
    local function errs(fields, prompt) local _, e = C().validate(fields, prompt or { "p" }, { task_id = "T-002" }); return e end
    local base = { Title = "x", Provider = "mock", Isolation = "shared", Dependencies = "", Priority = "50", Timeout = "1800" }
    local function with(p) return vim.tbl_extend("force", base, p) end
    t:eq(errs(with({ Dependencies = "T-999" }))[1].field, "Dependencies"); t:match(errs(with({ Dependencies = "T-999" }))[1].message, "unknown dependency")
    t:eq(errs(with({ Dependencies = "T-002" }))[1].field, "Dependencies"); t:match(errs(with({ Dependencies = "T-002" }))[1].message, "itself")
    S.tasks["T-001"].depends_on = { "T-002" }
    t:match(errs(with({ Dependencies = "T-001" }))[1].message, "cycle")
    t:eq(errs(with({ Priority = "-1" }))[1].field, "Priority"); t:eq(errs(with({ Timeout = "0" }))[1].field, "Timeout"); t:eq(errs(with({ Timeout = "abc" }))[1].field, "Timeout")
    local iso = errs(with({ Isolation = "worktree" })); t:eq(iso[1].field, "Isolation"); t:match(iso[1].message, "shared mode must be chosen explicitly")
    t:eq(#errs(with({ Isolation = "shared" })), 0)
    t:match(C().effective_cwd(with({ Isolation = "shared" })), "%(shared%)$")
    vim.env.AISWARM_WORKTREES = "/tmp/wts"; t:match(C().effective_cwd(with({ Isolation = "worktree" })), "/tmp/wts/<task%-id>"); vim.env.AISWARM_WORKTREES = nil
    t:eq(errs(base, { "", "  " })[1].field, "prompt")
  end },
  -- ------------------------------------------------------------ SDD-063
  { id = "composer.drafts_persist_and_stay_scoped", tasks = { "SDD-063" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root1, A = ui.board_with_tasks(t, 1, { name = "d1" })
    C().DRAFT_DEBOUNCE_MS = 20
    local buf = C().open({ fresh = true })
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "Title:        my draft" })
    vim.api.nvim_buf_set_lines(buf, 7, -1, false, { "draft prompt", "", "second" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    t:wait(2000, function() local _, st = current_composer(); return st and st.saved end, "autosaved")
    local _, st = current_composer(); local draft_id = st.draft_id
    -- Esc keeps the draft; reopening restores it
    st.win:close(); vim.wait(50)
    t:eq(#C().drafts(), 1); t:eq(C().drafts()[1].Title, "my draft")
    local buf2 = C().open({})
    t:eq(ui.lines(buf2)[1], "Title:        my draft"); t:eq(ui.lines(buf2, 7, -1), { "draft prompt", "", "second" })
    local _, st2 = current_composer(); t:eq(st2.draft_id, draft_id, "same draft resumed")
    -- concurrent second draft does not overwrite the first
    local buf3 = C().open({ fresh = true })
    vim.api.nvim_buf_set_lines(buf3, 0, 1, false, { "Title:        another" }); vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf3 })
    t:wait(2000, function() return #C().drafts() == 2 end, "two drafts")
    -- simulated editor restart: unload everything, drafts come back from disk
    for b, s in pairs(C().open_bufs) do if s.win and s.win:valid() then s.win:close() end end
    vim.wait(50)
    pl.setup(t, root1); pl.refresh(t, require("aiswarm"))
    t:eq(#C().drafts(), 2, "drafts restored after restart")
    -- project switch: the draft belongs to board 1 and cannot be submitted to board 2
    local root2 = v3.board(t, "d2")
    local buf4 = C().open({ draft = C().drafts()[1] })
    require("aiswarm.project").open(root2)
    local seen = pl.capture_notify(function() C().submit(buf4); vim.wait(100) end)
    t:match(seen[1].msg, "project changed")
    t:eq(#v3.cli_json(t, root2, { "snapshot" }).tasks, 0, "nothing submitted to the other board")
    -- discard removes only the chosen draft
    require("aiswarm.project").open(root1)
    local drafts = C().drafts(); C().discard_draft(drafts[1].draft_id)
    t:eq(#C().drafts(), 1); t:neq(C().drafts()[1].draft_id, drafts[1].draft_id)
    for b, s in pairs(C().open_bufs) do s.closed = true; if s.win and s.win:valid() then s.win:close() end end
  end },
  -- ------------------------------------------------------------ SDD-064
  { id = "composer.submit_edit_and_legacy_round_trip", tasks = { "SDD-064" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45)
    local root, A = ui.board_with_tasks(t, 1, { name = "sub" })
    local ws = ui.open(t)
    C().DRAFT_DEBOUNCE_MS = 20
    local buf = C().open({ fresh = true })
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "Title:        submitted task" })
    vim.api.nvim_buf_set_lines(buf, 7, -1, false, { "line one", "", "#: header-like line", "last line" })
    C().submit(buf); C().submit(buf)   -- duplicate save
    t:wait(10000, function() return store().task("T-002") ~= nil end, "task queued")
    vim.wait(300); pl.refresh(t, A)
    t:eq(store().task("T-003"), nil, "duplicate submission created one task")
    t:eq(sb.read(root .. "/prompts/T-002/r1.md"), "line one\n\n#: header-like line\nlast line\n", "prompt round-trips including blank and header-like lines")
    t:eq(V().selected.task_id, "T-002", "successful submission selects the queued task")
    t:eq(#C().drafts(), 0, "draft removed after success")
    -- edit with a stale revision: backend conflict keeps the draft and focuses the error
    local ebuf = C().open({ edit = "T-002" })
    local _, st = current_composer(); t:eq(st.expected_revision, 1)
    v3.cli_json(t, root, { "set", "T-002", "--expect-revision", "1", "--priority", "9" }) -- someone else edits first
    vim.api.nvim_buf_set_lines(ebuf, 0, 1, false, { "Title:        edited title" })
    local seen = pl.capture_notify(function() C().submit(ebuf); t:wait(10000, function() return #vim.diagnostic.get(ebuf) > 0 end, "conflict surfaced inline") end)
    t:match(seen[#seen].msg, "revision conflict"); t:ok(vim.api.nvim_buf_is_valid(ebuf), "draft buffer kept")
    t:eq(vim.api.nvim_win_get_cursor(0)[1], 1, "cursor on the first affected field")
    st.closed = true; st.win:close()
    -- successful edit carries the expected revision
    pl.refresh(t, A)
    local ebuf2 = C().open({ edit = "T-002" })
    local _, st2 = current_composer(); t:eq(st2.expected_revision, 2)
    vim.api.nvim_buf_set_lines(ebuf2, 0, 1, false, { "Title:        edited title" })
    C().submit(ebuf2)
    t:wait(10000, function() pl.refresh(t, A); return store().task("T-002").title == "edited title" end, "edit applied")
    t:eq(store().task("T-002").revision, 3)
    -- legacy #: form import/export through the same validator
    local fields, prompt = C().import_legacy({ "#: id = T-9", "#: title = old", "#: provider = mock", "#: deps = T-001", "#: priority = 7", "#: worktree = false", "#: timeout = 60", "---", "body", "", "#: kept" })
    t:eq(fields.Title, "old"); t:eq(fields.Dependencies, "T-001"); t:eq(prompt, { "body", "", "#: kept" })
    local exported = C().export_legacy(fields, prompt)
    local f2, p2 = C().import_legacy(exported); t:eq(f2, fields); t:eq(p2, prompt)
    local _, errs = C().validate(fields, prompt, {}); t:eq(#errs, 0)
  end },
  -- ------------------------------------------------------------ SDD-068
  { id = "journey.new_queue_inspect_cancel_retry_report", tasks = { "SDD-068" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45); kill_server(t)
    local root, A = ui.board_with_tasks(t, 0, { name = "journey" })
    local env = v3.provider_env("quiet", { AISWARM_FAKE_BARRIER = vim.fs.dirname(root) .. "/barrier" })
    A.env = (function(orig) return function() local e = orig(); for k, v in pairs(env) do e[k] = v end; return e end end)(A.env)
    local ws = ui.open(t)
    -- n: compose; type a prompt; Ctrl-s queues
    ui.keys("n"); vim.wait(100)
    local cbuf = vim.api.nvim_get_current_buf(); t:ok(vim.api.nvim_buf_get_name(cbuf):match("compose"))
    vim.cmd("stopinsert"); vim.api.nvim_buf_set_lines(cbuf, 7, -1, false, { "journey task" })
    ui.keys("<C-s>")
    t:wait(10000, function() return store().task("T-001") ~= nil end, "queued from the keyboard")
    ui.flush(); t:eq(V().selected.task_id, "T-001"); t:eq(ws.focus_name(), "tasks")
    -- Enter inspects (1 action), ] reaches Activity, Output, Report within two actions from the task
    ui.keys("<CR>"); t:eq(ws.focus_name(), "inspector"); t:eq(select(3, V().target()), "overview")
    ui.keys("]"); t:eq(select(3, V().target()), "activity"); ui.keys("]"); t:eq(select(3, V().target()), "output"); ui.keys("]"); t:eq(select(3, V().target()), "report")
    ui.keys("<BS>"); t:eq(ws.focus_name(), "tasks"); t:eq(V().selected.task_id, "T-001", "selection persists")
    -- dispatch the fixture worker, then x cancels with confirmation
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    t:wait(10000, function() pl.refresh(t, A); return store().task("T-001").state == "running" end, "running")
    ui.flush(); ui.keys("x")
    local actions = require("aiswarm.ui.actions")
    t:match(actions.last_confirm.text, "Cancel T%-001 · attempt 1 %(running%)")
    ui.keys("y")
    t:wait(20000, function() pl.refresh(t, A); return store().task("T-001").state == "cancelled" end, "cancelled")
    ui.flush(); t:eq(V().selected.task_id, "T-001"); t:ok(ws.is_open())
    -- r retries into a fresh attempt; the worker runs to completion; R shows the report
    ui.keys("r")
    t:wait(10000, function() pl.refresh(t, A); return store().task("T-001").state == "queued" end, "retried")
    sb.write(vim.fs.dirname(root) .. "/barrier", "go")
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    t:wait(20000, function() pl.refresh(t, A); return store().task("T-001").state == "succeeded" end, "second attempt succeeded")
    ui.flush(); ui.keys("R"); t:eq(select(3, V().target()), "report")
    t:wait(5000, function() ui.flush(); return ui.text(ws.buf("inspector")):find("fake quiet", 1, true) ~= nil end, "report of attempt 2 shown")
    t:eq(#store().attempts_of("T-001"), 2)
    -- Tab/Esc semantics: Tab cycles panes, Esc in the inspector returns to tasks (narrow contract also allows Backspace)
    ui.keys("<Tab>"); t:eq(ws.focus_name(), "activity"); ui.keys("<Esc>"); t:eq(ws.focus_name(), "tasks")
  end },
  { id = "journey.blocked_task_recovery", tasks = { "SDD-068" }, suites = { "core" }, run = function(t)
    need_snacks(t); ui.screen(140, 45); kill_server(t)
    local root, A = ui.board_with_tasks(t, 0, { name = "blocked" })
    local env = v3.provider_env("failure")
    v3.cli_json(t, root, { "add", "--id", "T-001", "--title", "upstream" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "add", "--id", "T-002", "--title", "downstream", "--dep", "T-001" }, { stdin = "y\n" })
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    t:wait(15000, function() pl.refresh(t, A); return store().task("T-001").state == "failed" end, "upstream failed")
    local ws = ui.open(t)
    local text = ui.text(ws.buf("tasks"))
    t:match(text, "Blocked%s+mock%s+blocked by T%-001", "blocker visible as text")
    t:match(text, "ATTENTION · 1")
    ws.inspect("T-002", nil, "overview"); ui.flush()
    t:match(ui.text(ws.buf("inspector")), "Blocked%s+blocked by T%-001 %(failed%)")
    -- recover: retry upstream (r on T-001) and let it succeed
    V().select("T-001"); ws.focus("tasks"); ws.render_all(); ui.flush()
    local row = require("aiswarm.ui.tasks").row_of(ws.rowmap, "T-001"); vim.api.nvim_win_set_cursor(ws.win_of("tasks"), { row, 0 }); ws.on_cursor()
    ui.keys("r")
    t:wait(10000, function() pl.refresh(t, A); return store().task("T-001").state == "queued" end, "retried upstream")
    ui.flush(); t:match(ui.text(ws.buf("tasks")), "waiting for T%-001")
    v3.cli_json(t, root, { "dispatch" }, { env = v3.provider_env("success") })
    t:wait(20000, function() pl.refresh(t, A); return store().task("T-001").state == "succeeded" end, "upstream succeeded")
    ui.flush()
    t:eq(store().task("T-002").display, "Queued", "downstream unblocked"); t:ok(not ui.text(ws.buf("tasks")):find("blocked by"))
  end },
}
