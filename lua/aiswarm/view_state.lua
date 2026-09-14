-- View selection model keyed by identity (SDD-047, ADR 0004).
local V = {}

function V.reset()
  V.selected = { task_id = nil, attempt_id = nil, index = nil }
  V.tab = "overview"
  V.pinned = nil            -- { task_id, attempt_id, tab }
  V.filter = { text = "", group = "all" }
  V.collapsed = { running = false, attention = false, queued = false, finished = false }
  V.feed = { follow = true, unread = 0, pinned = nil, filters = { min_level = "info", show_hidden = false, text = "" } }
  V.output = { follow = true, unread = 0, wrap = false, stream = "stdout", search = nil }
  V.focus = "tasks"
  V.version = 0
end
V.reset()
V.TABS = { "overview", "activity", "output", "report", "files", "attempts" }

local function bump() V.version = V.version + 1 end

--- Select a task (and optionally an attempt). `index` is its row position in the rendered list.
function V.select(task_id, attempt_id, index)
  if V.selected.task_id ~= task_id or V.selected.attempt_id ~= attempt_id then
    V.selected = { task_id = task_id, attempt_id = attempt_id, index = index }
    if not V.pinned then V.output.unread = 0 end
    bump()
    return true
  end
  V.selected.index = index or V.selected.index
  return false
end

--- The inspector target: pinned selection wins over the task cursor.
function V.target()
  if V.pinned then return V.pinned.task_id, V.pinned.attempt_id, V.pinned.tab end
  return V.selected.task_id, V.selected.attempt_id, V.tab
end

function V.pin(toggle)
  if V.pinned and toggle ~= true then V.pinned = nil; bump(); return false end
  if not V.selected.task_id then return false end
  V.pinned = { task_id = V.selected.task_id, attempt_id = V.selected.attempt_id, tab = V.tab }
  bump(); return true
end

function V.set_tab(tab)
  if V.pinned then V.pinned.tab = tab else V.tab = tab end
  bump()
end

--- Reconcile the selection with the visible rows: keep the same id when present; otherwise the
--- row now occupying the former index, else the previous one, else nothing.
---@param visible string[] ordered task ids
---@return boolean changed
function V.reconcile(visible)
  local sel = V.selected
  if sel.task_id then
    for i, id in ipairs(visible) do if id == sel.task_id then sel.index = i; return false end end
  end
  if #visible == 0 then
    if sel.task_id then V.selected = { task_id = nil, attempt_id = nil, index = nil }; bump(); return true end
    return false
  end
  local idx = sel.index or 1
  local pick = visible[math.min(idx, #visible)] or visible[#visible]
  V.selected = { task_id = pick, attempt_id = nil, index = math.min(idx, #visible) }
  bump()
  return true
end

function V.toggle_group(name) V.collapsed[name] = not V.collapsed[name]; bump() end
function V.set_filter(text, group) V.filter.text, V.filter.group = text or V.filter.text, group or V.filter.group; bump() end

return V
