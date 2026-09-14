-- Contextual action registry with identity/revision capture and re-validation (SDD-052).
local M = {}
local function A() return require("aiswarm") end
local store = require("aiswarm.store")
local V = require("aiswarm.view_state")
local backend = require("aiswarm.backend")

--- Capture an action target from the current store state.
function M.target(task_id, attempt_id)
  local t = task_id and store.task(task_id) or nil
  if not t then return nil end
  local a = attempt_id and store.attempt(attempt_id) or store.current_attempt(task_id)
  return { board_id = store.board.board_id, task_id = t.id, attempt_id = a and a.attempt_id or nil, revision = t.revision, state = t.state,
    ordinal = a and a.ordinal or nil, legacy = t.legacy }
end

local function caps(name) return store.capability(name) end
local TERMINAL = { succeeded = true, failed = true, cancelled = true }

--- Action definitions. legal(target, task) -> true | false, reason.
M.actions = {
  inspect  = { label = "Inspect", key = "<CR>", legal = function(tg) return tg ~= nil, "select a task" end },
  output   = { label = "Output", key = "t", legal = function(tg) return tg ~= nil, "select a task" end },
  report   = { label = "Report", key = "R", legal = function(tg) return tg ~= nil, "select a task" end },
  attach   = { label = "Attach tmux session", key = "g", legal = function(tg, t)
    if not tg then return false, "select a task" end
    if not vim.env.TMUX then return false, "not inside tmux" end
    return t.state == "running" or (t.session ~= nil) or (tg.attempt_id ~= nil), "no session for this task"
  end },
  edit     = { label = "Edit queued task", key = "e", legal = function(tg, t) if not tg then return false, "select a task" end return t.state == "queued", "only queued tasks can be edited" end },
  cancel   = { label = "Cancel", key = "x", legal = function(tg, t)
    if not tg then return false, "select a task" end
    if not caps("cancel") then return false, "cancel needs a v3 board (legacy boards only support kill = cancel and requeue)" end
    return not TERMINAL[t.state], t.id .. " is already " .. t.state
  end },
  retry    = { label = "Retry", key = "r", legal = function(tg, t)
    if not tg then return false, "select a task" end
    if not caps("retry") then return false, "retry needs a v3 board" end
    return TERMINAL[t.state] == true, "only finished tasks can be retried"
  end },
  kill     = { label = "Kill (legacy: cancel and requeue)", key = nil, legal = function(tg, t)
    if not tg then return false, "select a task" end
    return t.state == "running", "legacy kill needs a running task"
  end },
  pin      = { label = "Pin/unpin inspector", key = "p", legal = function(tg) return tg ~= nil, "select a task" end },
  transcript = { label = "Open full transcript", key = "o", legal = function(tg) return tg ~= nil, "select a task" end },
  copy_id  = { label = "Copy task id", key = "y", legal = function(tg) return tg ~= nil, "select a task" end },
  new      = { label = "New task", key = "n", legal = function() return true end },
  pause    = { label = "Toggle dispatch pause", key = "P", legal = function() return store.scheduler ~= nil, "no scheduler" end },
  refresh  = { label = "Reconcile now", key = "<C-r>", legal = function() return true end },
  scheduler_start = { label = "Start scheduler", key = "S", legal = function() return caps("attempts") and store.scheduler.state ~= "running", "scheduler already running or legacy board" end },
}
M.order = { "inspect", "output", "report", "attach", "edit", "cancel", "retry", "kill", "pin", "transcript", "copy_id", "new", "pause", "scheduler_start", "refresh" }

function M.legal(name, target)
  local def = M.actions[name]
  if not def then return false, "unknown action" end
  local task = target and store.task(target.task_id) or nil
  return def.legal(target, task)
end

--- Legal actions for a target, for the menu and footer hints.
function M.list(target)
  local out = {}
  for _, name in ipairs(M.order) do
    local ok, reason = M.legal(name, target)
    out[#out + 1] = { name = name, label = M.actions[name].label, key = M.actions[name].key, legal = ok, reason = reason }
  end
  return out
end

--- Small inline yes/no prompt. cb(true|false).
function M.confirm(text, cb)
  if not (package.loaded["snacks"] and _G.Snacks and Snacks.win) then
    return cb(vim.fn.confirm(text, "&Yes\n&No", 2) == 1)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text, "", "  y  yes        n / Esc  no" })
  vim.bo[buf].modifiable = false
  local prev = vim.api.nvim_get_current_win()
  local answered = false
  local win
  local function answer(v)
    if answered then return end
    answered = true
    if win and win:valid() then win:close() end
    if vim.api.nvim_win_is_valid(prev) then pcall(vim.api.nvim_set_current_win, prev) end
    cb(v)
  end
  -- zindex: the workspace layout floats sit above the Snacks default (50), so popups must be stacked on top explicitly
  win = Snacks.win({ buf = buf, width = math.max(30, #text + 4), height = 3, border = "rounded", title = " confirm ", title_pos = "center", enter = true, zindex = Snacks.win.zindex(60),
    bo = { bufhidden = "wipe" }, wo = { cursorline = false }, backdrop = false,
    keys = { y = function() answer(true) end, ["<CR>"] = function() answer(true) end, n = function() answer(false) end, ["<Esc>"] = function() answer(false) end, q = function() answer(false) end },
    on_close = function() if not answered then answered = true; cb(false) end end })
  M.last_confirm = { win = win, text = text }
end

--- Re-validate a captured target against the current store. Returns ok, message.
function M.revalidate(target)
  if not target then return false, "no task selected" end
  local t = store.task(target.task_id)
  if not t then return false, ("Task changed; review current state (%s no longer exists)"):format(target.task_id) end
  if target.revision and t.revision and t.revision ~= target.revision then return false, ("Task changed; review current state (%s is now revision %d)"):format(t.id, t.revision) end
  if target.state and t.state ~= target.state then return false, ("Task changed; review current state (%s is now %s)"):format(t.id, t.state) end
  return true
end

--- Execute an action for a captured target.
function M.run(name, target, opts)
  opts = opts or {}
  local def = M.actions[name]
  if not def then return A().err("unknown action: " .. tostring(name)) end
  local ok, reason = M.legal(name, target)
  if not ok then return A().warn(reason) end
  local ws = require("aiswarm.ui.workspace")
  local function conflict(msg) A().warn(msg); A().refresh() end
  if name == "inspect" then return ws.inspect(target.task_id, target.attempt_id, "overview")
  elseif name == "output" then return ws.inspect(target.task_id, target.attempt_id, "output")
  elseif name == "report" then return ws.inspect(target.task_id, target.attempt_id, "report")
  elseif name == "pin" then V.select(target.task_id, target.attempt_id); V.pin(); return ws.render_all()
  elseif name == "copy_id" then vim.fn.setreg("+", target.task_id); vim.fn.setreg('"', target.task_id); return A().notify("copied " .. target.task_id)
  elseif name == "new" then return require("aiswarm.ui.composer").open({})
  elseif name == "refresh" then
    local session = require("aiswarm.session")
    if session.transport and session.engine and session.engine.reconnect then session.engine.reconnect() else A().refresh() end
    return
  elseif name == "transcript" then return require("aiswarm.ui.inspector").open_transcript(target)
  elseif name == "attach" then
    local vok, msg = M.revalidate(target); if not vok then return conflict(msg) end
    if target.legacy then return require("aiswarm.legacy.ui").go(target.task_id) end
    return backend.run({ "attach", target.task_id }, { silent = false }, function(res)
      if res.ok then A().notify("attached " .. (res.data and res.data.session or target.task_id)) end
    end)
  elseif name == "edit" then
    local vok, msg = M.revalidate(target); if not vok then return conflict(msg) end
    return require("aiswarm.ui.composer").open({ edit = target.task_id })
  elseif name == "pause" then return A().toggle_pause()
  elseif name == "scheduler_start" then return A().scheduler("start")
  elseif name == "cancel" then
    local t = store.task(target.task_id)
    local label = ("Cancel %s%s (%s)?"):format(target.task_id, target.ordinal and (" · attempt " .. target.ordinal) or "", t.state)
    local function go()
      local vok, msg = M.revalidate(target); if not vok then return conflict(msg) end
      local args = { "cancel", target.task_id }
      if target.revision then vim.list_extend(args, { "--expect-revision", tostring(target.revision) }) end
      if target.attempt_id and t.state == "running" then vim.list_extend(args, { "--attempt", target.attempt_id }) end
      backend.call(args, { timeout_ms = 30000 }, function(res)
        if res.ok then A().notify("cancelled " .. target.task_id); A().refresh()
        elseif res.code == 3 then conflict(res.error or "Task changed; review current state")
        elseif not res.stale then A().err(res.error or "cancel failed") end
      end)
    end
    if opts.confirmed then return go() end
    return M.confirm(label, function(yes) if yes then go() end end)
  elseif name == "retry" then
    local vok, msg = M.revalidate(target); if not vok then return conflict(msg) end
    local args = { "retry", target.task_id }
    if target.revision then vim.list_extend(args, { "--expect-revision", tostring(target.revision) }) end
    return backend.call(args, {}, function(res)
      if res.ok then A().notify("retrying " .. target.task_id); A().refresh()
      elseif res.code == 3 then conflict(res.error or "Task changed; review current state")
      elseif not res.stale then A().err(res.error or "retry failed") end
    end)
  elseif name == "kill" then
    local vok, msg = M.revalidate(target); if not vok then return conflict(msg) end
    A().warn("legacy kill: " .. target.task_id .. " will be cancelled and requeued")
    return A().kill(target.task_id)
  end
end

--- Resolve an omitted id: explicit arg → workspace selection → task picker. cb(task_id).
function M.resolve_id(id, cb)
  if id and id ~= "" then
    if not store.task(id) then A().err("no such task: " .. id); return end
    return cb(id)
  end
  local sel = V.selected.task_id
  local ws = require("aiswarm.ui.workspace")
  if sel and ws.is_open() and store.task(sel) then return cb(sel) end
  require("aiswarm.ui.picker").pick({ prompt = "select a task", on_select = cb })
end

--- Action menu for the current target.
function M.menu(target)
  local items = M.list(target)
  local labels = {}
  for _, it in ipairs(items) do
    labels[#labels + 1] = ("%-4s %-28s%s"):format(it.key or "", it.label, it.legal and "" or ("  (" .. tostring(it.reason) .. ")"))
  end
  vim.ui.select(labels, { prompt = target and ("Actions for " .. target.task_id) or "Actions" }, function(_, idx)
    if not idx then return end
    local it = items[idx]
    if not it.legal then return A().warn(it.reason) end
    M.run(it.name, M.target(target and target.task_id, target and target.attempt_id))
  end)
end

return M
