-- Notification policy (SDD-067): actionable failures/completions/input requests only, burst
-- aggregation, deduplication, persistent attention badge, one owner per local session.
local M = { seen = {}, pending = {}, timer = nil, stats = { toasts = 0, suppressed = 0 } }
local function A() return require("aiswarm") end
local store = require("aiswarm.store")

M.WINDOW_MS = 1500

local function key_of(task, kind)
  local out = task.outcome or {}
  return ("%s:%s:%s"):format(task.id, kind, tostring(out.finished_at or out.attempt_id or task.revision))
end

local function flush()
  M.timer = nil
  local items = M.pending
  M.pending = {}
  if #items == 0 then return end
  M.stats.toasts = M.stats.toasts + 1
  if #items == 1 then
    local it = items[1]
    return A().notify(it.text, it.level)
  end
  local lines, level = {}, vim.log.levels.INFO
  for _, it in ipairs(items) do lines[#lines + 1] = it.short; if it.level == vim.log.levels.ERROR then level = vim.log.levels.ERROR end end
  A().notify(("%d updates\n%s"):format(#items, table.concat(lines, "\n")), level)
end

local function enqueue(item)
  if M.seen[item.key] then M.stats.suppressed = M.stats.suppressed + 1; return end
  M.seen[item.key] = true
  M.pending[#M.pending + 1] = item
  if not M.timer then M.timer = vim.defer_fn(flush, M.WINDOW_MS) end
end

--- Inspect a task transition and enqueue a notification when the policy allows it.
function M.on_task(task, prev)
  local cfg = A().config.notify
  if not task or (prev and prev.state == task.state and (prev.outcome and prev.outcome.finished_at) == (task.outcome and task.outcome.finished_at)) then return end
  if task.state == "failed" and cfg.failed then
    local reason = task.outcome and task.outcome.reason or "failed"
    enqueue({ key = key_of(task, "failed"), level = vim.log.levels.ERROR, text = ("%s failed: %s\n%s"):format(task.id, reason, task.title or ""), short = ("✗ %s %s"):format(task.id, reason) })
  elseif task.state == "succeeded" and cfg.completed then
    enqueue({ key = key_of(task, "succeeded"), level = vim.log.levels.INFO, text = ("%s completed\n%s"):format(task.id, task.title or ""), short = ("✓ %s"):format(task.id) })
  elseif task.state == "running" and cfg.started and (not prev or prev.state ~= "running") then
    enqueue({ key = key_of(task, "started"), level = vim.log.levels.INFO, text = ("%s started"):format(task.id), short = ("● %s started"):format(task.id) })
  end
end

function M.on_activity(rec)
  local cfg = A().config.notify
  if rec.kind == "input_required" and cfg.input_required then
    enqueue({ key = "input:" .. tostring(rec.event_id), level = vim.log.levels.WARN, text = ("%s is waiting for input\n%s"):format(rec.task_id or "?", rec.text or ""), short = ("? %s input"):format(rec.task_id or "?") })
  elseif rec.kind == "progress" and cfg.progress then
    enqueue({ key = "progress:" .. tostring(rec.event_id), level = vim.log.levels.INFO, text = ("%s: %s"):format(rec.task_id or "?", rec.text or ""), short = ("· %s %s"):format(rec.task_id or "?", rec.text or "") })
  end
end

--- Attach to the store; the first snapshot after attach is history and never toasts.
function M.attach()
  if M.unsub then M.unsub() end
  M.seen, M.pending = {}, {}
  local prev, primed = {}, false
  M.unsub = store.subscribe(function(change)
    if change.kind == "snapshot" then
      for id, t in pairs(store.tasks) do if primed then M.on_task(t, prev[id]) end; prev[id] = t end
      primed = true
    elseif change.kind == "control" then
      for _, id in ipairs(change.ids or {}) do local t = store.task(id); if primed and t and not change.historical then M.on_task(t, prev[id]) end; prev[id] = t end
    elseif change.kind == "activity" and change.record and primed then
      M.on_activity(change.record)
    end
  end)
  return M.unsub
end
function M.detach() if M.unsub then M.unsub(); M.unsub = nil end end

--- Declare this editor the notification owner for the board (single owner across channels).
function M.claim_owner(root)
  if not root then return end
  pcall(vim.fn.writefile, { tostring(vim.v.servername ~= "" and vim.v.servername or ("nvim:" .. vim.fn.getpid())) }, root .. "/notify.owner")
end

return M
