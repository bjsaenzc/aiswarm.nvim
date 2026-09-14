-- Persistent workspace shell (SDD-049, SDD-053, SDD-065): one Snacks layout owning the panes,
-- buffer-local key contract from ADR 0004, responsive relayout, first-use/offline states.
local M = { bufs = {}, wins = {}, layout = nil, mode = nil, rowmap = {}, visible = {}, subs = {}, timers = {} }
local function A() return require("aiswarm") end
local store = require("aiswarm.store")
local V = require("aiswarm.view_state")
local R = require("aiswarm.ui.render")
local T = require("aiswarm.ui.text")
local L = require("aiswarm.ui.layout")
local project = require("aiswarm.project")
local ns = vim.api.nvim_create_namespace("aiswarm-workspace")

M.stats = { opens = 0, relayouts = 0 }

function M.available() return package.loaded["snacks"] ~= nil or pcall(require, "snacks") end
function M.is_open() return M.layout ~= nil and not M.layout.closed end

-- ---------------------------------------------------------------- buffers
local function scratch(name, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile, vim.bo[buf].modifiable = "nofile", "hide", false, false
  vim.bo[buf].undolevels = -1   -- rendered views are rebuilt constantly; undo history would grow without bound
  vim.bo[buf].filetype = ft
  pcall(vim.api.nvim_buf_set_name, buf, "aiswarm://" .. name)
  return buf
end
local function ensure_bufs()
  for _, name in ipairs({ "tasks", "inspector", "activity" }) do
    if not (M.bufs[name] and vim.api.nvim_buf_is_valid(M.bufs[name])) then
      M.bufs[name] = scratch(name, "aiswarm-" .. name)
      M.map_keys(name, M.bufs[name])
    end
  end
end
function M.buf(name) return M.bufs[name] end

--- Window handle currently showing a pane buffer (nil when hidden).
function M.win_of(name)
  local buf = M.bufs[name]
  if not buf then return nil end
  for _, win in pairs(M.wins) do
    if win:valid() and win.buf == buf then return win.win end
  end
  return nil
end
function M.pane_visible(name) return M.win_of(name) ~= nil end

-- ---------------------------------------------------------------- keys (ADR 0004)
local function map(buf, lhs, fn, desc, mode)
  vim.keymap.set(mode or "n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = "aiswarm: " .. desc })
end
--- Action target for the pane: in the task list it is the task under the cursor (a header or blank
--- row has no target); elsewhere it is the inspector target.
function M.target_at_cursor(name)
  local actions = require("aiswarm.ui.actions")
  if name == "tasks" then
    local win = M.win_of("tasks")
    if win and vim.api.nvim_get_current_win() == win then
      local entry = M.rowmap[vim.api.nvim_win_get_cursor(win)[1]]
      if not entry or not entry.task_id then return nil end
      return actions.target(entry.task_id, nil)
    end
    return actions.target(V.selected.task_id, V.selected.attempt_id)
  end
  local task_id, attempt_id = V.target()
  return actions.target(task_id, attempt_id)
end

function M.map_keys(name, buf)
  local actions = require("aiswarm.ui.actions")
  local function tg() return M.target_at_cursor(name) end
  -- common
  map(buf, "q", function() M.close() end, "close workspace")
  map(buf, "<Tab>", function() M.cycle(1) end, "next pane")
  map(buf, "<S-Tab>", function() M.cycle(-1) end, "previous pane")
  map(buf, "?", function() actions.menu(tg()) end, "action menu")
  map(buf, "n", function() actions.run("new", nil) end, "new task")
  map(buf, "P", function() actions.run("pause", nil) end, "toggle dispatch pause")
  map(buf, "<C-r>", function() actions.run("refresh", nil) end, "reconcile")
  map(buf, "p", function()
    if M.mode == "minimal" then return require("aiswarm.ui.picker").pick() end
    local t = tg(); if t then actions.run("pin", t) end
  end, "pin inspector (minimal layout: task picker)")
  map(buf, "S", function() actions.run("scheduler_start", nil) end, "start scheduler")
  map(buf, "c", function() if M.state_kind() == "no_board" then require("aiswarm.ui.project").init({}) end end, "create board")
  map(buf, "o", function() if M.state_kind() == "no_board" then require("aiswarm.ui.project").run({ "choose" }) else local t = tg(); if t then actions.run("transcript", t) end end end, "open board / transcript")
  map(buf, "h", function() if M.state_kind() == "no_board" then A().health() end end, "health")
  if name == "tasks" then
    map(buf, "<CR>", function() M.enter() end, "inspect / toggle group")
    map(buf, "t", function() local t = tg(); if t then actions.run("output", t) end end, "output")
    map(buf, "R", function() local t = tg(); if t then actions.run("report", t) end end, "report")
    map(buf, "g", function() local t = tg(); if t then actions.run("attach", t) end end, "attach")
    map(buf, "e", function() local t = tg(); if t then actions.run("edit", t) end end, "edit")
    map(buf, "x", function() local t = tg(); if t then actions.run("cancel", t) end end, "cancel")
    map(buf, "r", function() local t = tg(); if t then actions.run("retry", t) end end, "retry")
    map(buf, "y", function() local t = tg(); if t then actions.run("copy_id", t) end end, "copy id")
    map(buf, "/", function() M.prompt_filter() end, "filter")
    map(buf, "<Esc>", function() if V.filter.text ~= "" then V.set_filter(""); M.render_all() end end, "clear filter")
    map(buf, "za", function() M.toggle_group_at_cursor() end, "toggle group")
    map(buf, "zc", function() M.toggle_group_at_cursor(true) end, "collapse group")
    map(buf, "zo", function() M.toggle_group_at_cursor(false) end, "expand group")
    for i, g in ipairs({ "all", "running", "queued", "attention", "finished" }) do
      map(buf, tostring(i), function() V.set_filter(nil, g); M.render_all() end, "filter " .. g)
    end
  elseif name == "inspector" then
    local I = require("aiswarm.ui.inspector")
    map(buf, "]", function() I.cycle_tab(1) end, "next tab"); map(buf, "[", function() I.cycle_tab(-1) end, "previous tab")
    map(buf, "L", function() I.cycle_tab(1) end, "next tab"); map(buf, "H", function() I.cycle_tab(-1) end, "previous tab")
    map(buf, "f", function() I.toggle_follow() end, "pause/resume view following")
    map(buf, "s", function() I.toggle_stream() end, "stdout/stderr")
    map(buf, "w", function() I.toggle_wrap() end, "wrap")
    map(buf, "<CR>", function() I.enter() end, "open item")
    map(buf, "d", function() I.diff_at_cursor() end, "diff file")
    map(buf, "<BS>", function() M.back() end, "back to tasks")
    map(buf, "<Esc>", function() M.back() end, "back to tasks")
    map(buf, "x", function() local t = tg(); if t then actions.run("cancel", t) end end, "cancel")
    map(buf, "r", function() local t = tg(); if t then actions.run("retry", t) end end, "retry")
    map(buf, "g", function() local t = tg(); if t then actions.run("attach", t) end end, "attach")
    map(buf, "G", function() I.jump_end() end, "end (resume following)")
  elseif name == "activity" then
    local Act = require("aiswarm.ui.activity")
    map(buf, "f", function() Act.toggle_follow() end, "pause/resume view following")
    map(buf, "/", function() Act.prompt_filter() end, "filter activity")
    map(buf, "<BS>", function() M.back() end, "back to tasks")
    map(buf, "<Esc>", function() M.back() end, "back to tasks")
    map(buf, "G", function() Act.jump_end() end, "end (resume following)")
    map(buf, "<CR>", function() Act.enter() end, "inspect task of entry")
    map(buf, "v", function() Act.toggle_verbose() end, "verbose (heartbeats/raw output)")
  end
end

-- ---------------------------------------------------------------- state kinds (SDD-065)
function M.state_kind()
  local cur = project.current
  if not cur then
    local r = A()._resolved or {}
    if r.schema == "conflict" then return "conflict" end
    return "no_board"
  end
  local schema = cur.schema or project.schema(cur.root)
  if schema == "missing" then return "no_board" end
  if schema == "migrating" then return "migrating" end
  if store.connection.state == "offline" or store.connection.state == "incompatible" then return "offline" end
  if store.connection.state == "connecting" then return "loading" end
  if schema == "v3" and store.scheduler.state ~= "running" and store.counts().all > 0 then return "scheduler_stopped" end
  return "ready"
end

local function state_lines(kind, width)
  local r = A()._resolved or {}
  local lines = {}
  local function add(text, hl) lines[#lines + 1] = { text, hl and { { 0, #text, hl } } or {} } end
  if kind == "no_board" then
    add(""); add("  No aiswarm board in " .. tostring(r.root and vim.fs.dirname(r.root) or vim.uv.cwd()), "AISwarmTitle"); add("")
    add("  c   create a board here (" .. tostring(r.root) .. ")", "AISwarmValue")
    add("  o   open an existing board", "AISwarmValue")
    add("  h   health diagnostics", "AISwarmValue"); add("")
    add("  Opening the workspace never creates a board; creation is explicit.", "AISwarmMuted")
    local reg = require("aiswarm.providers.registry")
    add(""); add("  Providers:", "AISwarmHeader")
    for _, p in ipairs(reg.list()) do add(("    %-8s %s%s"):format(p.id, p.available and "available" or ("unavailable (" .. tostring(p.exe) .. " not found)"), p.id == "mock" and " · simulated execution, spends no tokens" or ""), p.available and "AISwarmDone" or "AISwarmMuted") end
  elseif kind == "conflict" then
    add(""); add("  Both .aiswarm and .hive exist in " .. tostring(r.dir), "AISwarmBlocked"); add("")
    add("  o   choose which board to open (:AISwarm project choose)", "AISwarmValue")
  elseif kind == "migrating" then
    add(""); add("  Interrupted migration on this board.", "AISwarmBlocked"); add("")
    add("  :AISwarm migrate --resume    finish the upgrade", "AISwarmValue"); add("  :AISwarm migrate --rollback  restore the v2 board", "AISwarmValue")
  elseif kind == "loading" then
    add(""); add("  Connecting to " .. tostring(project.root()) .. " …", "AISwarmMuted")
  end
  return lines
end

--- Banner shown above the task list for offline/stopped/legacy states.
function M.banner()
  local kind = M.state_kind()
  local cur = project.current
  if kind == "offline" then
    local age = store.connection.last_success and math.floor((vim.uv.now() - store.connection.last_success) / 1000) or nil
    return ("offline · cached %s ago · Ctrl-r · %s"):format(age and T.age(age) or "?", tostring(store.connection.error)), "AISwarmFailed"
  elseif kind == "scheduler_stopped" then
    return "scheduler stopped: queued tasks wait until it runs · S to start", "AISwarmBlocked"
  elseif cur and cur.schema == "v2" then
    return "legacy board (v2): no attempt history, cancel/retry or telemetry · :AISwarm migrate --dry-run", "AISwarmBlocked"
  elseif store.scheduler.paused then
    return "dispatch paused · P to resume", "AISwarmBlocked"
  end
  return nil
end

-- ---------------------------------------------------------------- rendering
function M.render_tasks()
  local buf = M.bufs.tasks
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local win = M.win_of("tasks")
  local width = win and vim.api.nvim_win_get_width(win) or 60
  local kind = M.state_kind()
  local lines, rowmap, visible = {}, {}, {}
  if M.mode == "minimal" then
    local c = store.counts()
    lines = { { "aiswarm needs at least 40×12 cells", { { 0, 40, "AISwarmTitle" } } },
      { ("running %d  queued %d  attention %d  done %d"):format(c.running, c.queued, c.attention, c.finished), { { 0, 60, "AISwarmMuted" } } },
      { "p  task picker      :  commands", { { 0, 40, "AISwarmHint" } } }, { "q  close", { { 0, 10, "AISwarmHint" } } } }
  elseif kind == "no_board" or kind == "conflict" or kind == "migrating" or kind == "loading" then
    lines = state_lines(kind, width)
  else
    local banner, hl = M.banner()
    local tl, rm, vis = require("aiswarm.ui.tasks").build(store, V, { width = width })
    if banner then
      lines[1] = { " " .. T.truncate(banner, width - 2), { { 0, #(" " .. T.truncate(banner, width - 2)), hl } } }
      for i, l in ipairs(tl) do lines[i + 1] = l end
      for i, r in pairs(rm) do rowmap[i + 1] = r end
    else lines, rowmap = tl, rm end
    visible = vis
  end
  M.rowmap, M.visible = rowmap, visible
  local changed = M.mode ~= "minimal" and V.reconcile(visible) or false   -- minimal shows no rows; keep the selection
  T.set_lines(buf, ns, lines)
  -- restore the cursor on the selected task without stealing focus
  if win and V.selected.task_id then
    local row = require("aiswarm.ui.tasks").row_of(rowmap, V.selected.task_id)
    if row then
      local cur = vim.api.nvim_win_get_cursor(win)[1]
      if (rowmap[cur] or {}).task_id ~= V.selected.task_id then
        M._setting_cursor = true
        pcall(vim.api.nvim_win_set_cursor, win, { row, 0 })
        M._setting_cursor = false
      end
    end
  end
  if changed then R.mark("inspector") end
  M.update_chrome()
end

function M.render_all()
  R.mark("tasks"); R.mark("inspector"); R.mark("activity")
end

--- Health/progress changes only touch secondary row text: redraw the list at most every 250 ms.
M.HEALTH_REDRAW_MS = 250
function M.mark_tasks_throttled()
  if M._health_timer then return end
  M._health_timer = vim.defer_fn(function() M._health_timer = nil; R.mark("tasks") end, M.HEALTH_REDRAW_MS)
end

function M.update_chrome()
  if not M.is_open() then return end
  local root = M.layout.root
  local cur = project.current
  local sched = store.scheduler or {}
  local counts = store.counts()
  local status
  if sched.state == "running" then status = ("Scheduler running · %d/%s workers"):format(counts.running, tostring(sched.wip or "?"))
  elseif sched.state == "stopped" then status = "Scheduler stopped"
  elseif sched.legacy then status = sched.paused and "Legacy scheduler (paused)" or "Legacy scheduler"
  else status = "Scheduler " .. tostring(sched.state) end
  if sched.paused and sched.state == "running" then status = status .. " · paused" end
  local conn = store.connection.state
  if conn ~= "live" then status = status .. " · " .. conn end
  local name = cur and (cur.root and vim.fs.basename(vim.fs.dirname(cur.root))) or "no board"
  local badge = counts.unacknowledged > 0 and (" " .. T.icons().attention .. counts.unacknowledged .. " ") or ""
  -- title and footer must fit inside the border line; overflow would be clipped by the terminal
  local width = (M.dims and M.dims.w or 80) - 4
  root.opts.title = " " .. T.truncate("aiswarm  " .. name .. badge .. "   " .. status, math.max(8, width)) .. " "
  root.opts.footer = " " .. T.truncate(M.hints(math.max(8, width - 2)), math.max(8, width)) .. " "
  if root:valid() then pcall(root.update, root) end
end

--- Footer hints follow the focused pane and shrink with the pane: the longest variant that fits the
--- border line wins, so the close/actions hints survive every width instead of being clipped (SDD-098).
function M.hint_variants()
  local focus = M.focus_name()
  local narrow = M.mode == "narrow" or M.mode == "minimal"
  if M.mode == "minimal" then return { "p picker   : command   q close", "p picker  : cmd  q close", "p picker  q close", "p  q" } end
  if M.state_kind() == "no_board" then return { "c create board   o open board   h health   q close", "c create  o open  h health  q close", "c o h  q close", "c  q" } end
  local back = narrow and "Backspace tasks   " or "Tab next pane   "
  if focus == "inspector" then
    local I = require("aiswarm.ui.inspector")
    local full = "[ ] tabs   f pause view   o transcript   x cancel   r retry   p pin   ? actions   q close"
    local medium = "[ ] tabs  f pause  o log  x cancel  r retry  ? actions  q close"
    if I.tab() == "output" or I.tab() == "activity" then
      local f = I.following() and "pause view" or "resume view"
      full = "[ ] tabs   f " .. f .. "   G end   s stream   w wrap   o transcript   q close"
      medium = "[ ] tabs  f " .. (I.following() and "pause" or "resume") .. "  G end  s stream  w wrap  q close"
    end
    return { back .. full, medium, "[ ] tabs  f pause  o log  x r  BS back  q", "? more  q" }
  elseif focus == "activity" then
    local f = V.feed.follow and "pause view" or "resume view"
    return { back .. "f " .. f .. "   / filter   p pin   v verbose   Enter inspect   q close", "f " .. (V.feed.follow and "pause" or "resume") .. "  / filter  p pin  v verbose  Enter inspect  q close", "f pause  / filter  BS back  q", "? more  q" }
  end
  return {
    "Enter inspect   t output   R report   n new   e edit   x cancel   r retry   / filter   P pause   ? actions   q close",
    "Enter inspect  t output  n new  e edit  x cancel  r retry  / filter  ? actions  q close",
    "Enter  t out  R rep  n new  x r  ? more  q",
    "? more  q",
  }
end

--- The footer text for the given budget (columns); defaults to the current layout width.
function M.hints(avail)
  avail = avail or ((M.dims and M.dims.w or 80) - 6)
  local variants = M.hint_variants()
  for _, v in ipairs(variants) do if vim.api.nvim_strwidth(v) <= avail then return v end end
  return variants[#variants]
end

-- ---------------------------------------------------------------- layout lifecycle
function M.focus_name()
  local cur = vim.api.nvim_get_current_win()
  for name in pairs(M.bufs) do
    if M.win_of(name) == cur then return name end
  end
  return V.focus
end

local function make_win(buf, name)
  return Snacks.win({ buf = buf, show = false, enter = false, backdrop = false, border = "none", minimal = true, resize = false, keys = { q = false, ["<esc>"] = false },
    wo = { cursorline = name ~= "inspector", wrap = false, number = false, relativenumber = false, signcolumn = "no", foldenable = false, winhighlight = "NormalFloat:Normal,FloatBorder:AISwarmBorder" },
    on_win = function(self) end })
end

function M.build(mode)
  local def, _, dims = L.definition(mode)
  M.dims = dims
  M.wins = {}
  if mode == "wide" or mode == "medium" then
    M.wins.tasks = make_win(M.bufs.tasks, "tasks")
    M.wins.inspector = make_win(M.bufs.inspector, "inspector")
    if mode == "wide" then M.wins.activity = make_win(M.bufs.activity, "activity") end
  else
    local first = V.focus == "inspector" and "inspector" or (V.focus == "activity" and "activity" or "tasks")
    if mode == "minimal" then first = "tasks" end
    M.wins.main = make_win(M.bufs[first], first)
  end
  M.layout = Snacks.layout.new({
    show = false, wins = M.wins, layout = def,
    on_close = function() M.on_close() end,
    on_update = function() M.update_chrome() end,
  })
  M.layout:show()
  M.mode = mode
  M.update_chrome()
end

function M.open(opts)
  opts = opts or {}
  if not M.available() then return A().err("snacks.nvim is required for the workspace") end
  require("aiswarm.ui.highlights").setup()
  if M.is_open() then
    M.focus(V.focus)
    if opts.task then M.inspect(opts.task, nil, opts.tab) end
    A().refresh()
    return M
  end
  M.stats.opens = M.stats.opens + 1
  M._released = false
  ensure_bufs()
  M.prev_win = vim.api.nvim_get_current_win()
  local w, h = L.interior()
  M.build(L.resolve(w, h))
  -- subscriptions
  M.subs = {}
  M.subs[#M.subs + 1] = store.subscribe(function(change)
    if change.kind == "activity" then R.mark("activity"); if require("aiswarm.ui.inspector").tab() == "activity" then R.mark("inspector") end
    elseif change.kind == "health" then M.mark_tasks_throttled(); R.mark("inspector")
    else R.mark("tasks"); R.mark("inspector"); if change.kind == "snapshot" or change.kind == "control" then R.mark("activity") end end
  end)
  M.subs[#M.subs + 1] = project.on_change(function() M.render_all() end)
  R.register("tasks", { render = M.render_tasks, visible = function() return M.pane_visible("tasks") end })
  R.register("inspector", { render = function() require("aiswarm.ui.inspector").render() end, visible = function() return M.pane_visible("inspector") end })
  R.register("activity", { render = function() require("aiswarm.ui.activity").render() end, visible = function() return M.pane_visible("activity") end })
  M.aug = vim.api.nvim_create_augroup("AISwarmWorkspace", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", { group = M.aug, buffer = M.bufs.tasks, callback = function() M.on_cursor() end })
  vim.api.nvim_create_autocmd("VimResized", { group = M.aug, callback = function() vim.schedule(M.relayout) end })
  vim.api.nvim_create_autocmd("WinEnter", { group = M.aug, callback = function() if M.is_open() then local n = M.focus_name(); if M.bufs[n] then V.focus = n; M.update_chrome() end end end })
  if M.mode ~= "minimal" and not V.selected.task_id then
    local g = store.grouped(V.filter)
    for _, name in ipairs(store.GROUPS) do if g.groups[name][1] then V.select(g.groups[name][1].id, nil, 1); break end end
  end
  M.render_tasks(); require("aiswarm.ui.inspector").render(); require("aiswarm.ui.activity").render()
  if opts.task then M.inspect(opts.task, nil, opts.tab) else M.focus("tasks") end
  A().refresh()
  return M
end

function M.on_close()
  if M._released then return end
  M._released = true
  -- release only view resources: never the scheduler, workers or the session
  for _, unsub in ipairs(M.subs) do pcall(unsub) end
  M.subs = {}
  for _, name in ipairs({ "tasks", "inspector", "activity" }) do R.unregister(name) end
  if M.aug then pcall(vim.api.nvim_del_augroup_by_id, M.aug); M.aug = nil end
  require("aiswarm.ui.inspector").clear()
  M.layout, M.wins = nil, {}
  if M.prev_win and vim.api.nvim_win_is_valid(M.prev_win) then pcall(vim.api.nvim_set_current_win, M.prev_win) end
end

function M.close()
  if not M.is_open() then return end
  local layout = M.layout
  M.layout = nil
  layout:close()
  M.on_close()
end

--- Recompute the layout after a resize; keeps buffers, selection, tabs and scroll state.
function M.relayout()
  if not M.is_open() then return end
  local w, h = L.interior()
  local mode = L.resolve(w, h)
  if mode == M.mode then return M.layout:update() end
  M.stats.relayouts = M.stats.relayouts + 1
  local focus = V.focus
  if M.mode == "minimal" and M._focus_before_minimal then focus = M._focus_before_minimal; M._focus_before_minimal = nil end
  if mode == "minimal" then M._focus_before_minimal = focus end
  local layout = M.layout
  M.layout = nil
  layout.opts.on_close = function() end
  layout:close()
  M._released = false
  M.build(mode)
  M.render_tasks(); require("aiswarm.ui.inspector").render(); require("aiswarm.ui.activity").render()
  M.focus(focus)
end

-- ---------------------------------------------------------------- focus and navigation
function M.focus(name)
  if not M.is_open() then return end
  if M.mode == "narrow" or M.mode == "minimal" then
    if M.mode == "minimal" then M._focus_before_minimal = M._focus_before_minimal or name; name = "tasks" end
    local win = M.wins.main
    if win and win:valid() and win.buf ~= M.bufs[name] then
      win:set_buf(M.bufs[name])
      vim.wo[win.win].cursorline = name ~= "inspector"
    end
    V.focus = name
    if win and win:valid() then pcall(vim.api.nvim_set_current_win, win.win) end
    R.mark(name); M.update_chrome()
    return
  end
  local win = M.win_of(name)
  if not win then name = "tasks"; win = M.win_of("tasks") end
  if win then pcall(vim.api.nvim_set_current_win, win) end
  V.focus = name
  M.update_chrome()
end

function M.cycle(dir)
  local panes = (M.mode == "wide") and { "tasks", "inspector", "activity" } or ((M.mode == "medium") and { "tasks", "inspector" } or { "tasks", "inspector", "activity" })
  local cur = V.focus
  local idx = 1
  for i, p in ipairs(panes) do if p == cur then idx = i end end
  M.focus(panes[(idx - 1 + dir) % #panes + 1])
end

function M.back() M.focus("tasks") end

function M.on_cursor()
  if M._setting_cursor then return end
  local win = M.win_of("tasks"); if not win then return end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local entry = M.rowmap[row]
  if entry and entry.task_id then
    local index = 0
    for _, id in ipairs(M.visible) do index = index + 1; if id == entry.task_id then break end end
    if V.select(entry.task_id, nil, index) then
      M.render_tasks_selection_only()
      R.mark("inspector")
    end
  end
end
function M.render_tasks_selection_only() R.mark("tasks") end

function M.enter()
  local win = M.win_of("tasks"); if not win then return end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local entry = M.rowmap[row]
  if not entry then return end
  if entry.task_id then return M.inspect(entry.task_id, nil, nil) end
  if entry.group then V.toggle_group(entry.group); return R.mark("tasks") end
end

function M.toggle_group_at_cursor(collapse)
  local win = M.win_of("tasks"); if not win then return end
  local entry = M.rowmap[vim.api.nvim_win_get_cursor(win)[1]]
  local g = entry and entry.group
  if not g then return end
  if collapse == nil then V.toggle_group(g) else V.collapsed[g] = collapse; V.version = V.version + 1 end
  R.mark("tasks")
end

--- Inspect a task: select it, set the tab and focus the inspector (narrow: navigate in).
function M.inspect(task_id, attempt_id, tab)
  if not M.is_open() then return M.open({ task = task_id, tab = tab }) end
  V.select(task_id, attempt_id)
  if tab then V.set_tab(tab) end
  store.acknowledge(task_id)
  R.mark("tasks"); R.mark("inspector")
  M.focus("inspector")
end

function M.prompt_filter()
  vim.ui.input({ prompt = "filter tasks: ", default = V.filter.text }, function(text)
    if text == nil then return end
    V.set_filter(text); M.render_all()
  end)
end

return M
