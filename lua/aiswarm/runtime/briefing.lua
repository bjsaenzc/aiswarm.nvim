-- Bounded orchestrator briefings (SDD-087): failures first, then blockers, then progress, with
-- event/attempt references; explicit truncation; no invented state.
local M = {}
M.LIMITS = { tasks = 20, chars = 4000, activity_per_task = 2 }

--- Build a briefing from a derived snapshot and recent activity records.
function M.build(snap, activity, opts)
  opts = opts or {}
  local limits = vim.tbl_extend("force", M.LIMITS, opts.limits or {})
  local by_task = {}
  for _, t in ipairs(snap.tasks) do by_task[t.id] = t end
  local latest = {}
  for _, r in ipairs(activity or {}) do
    if r.task_id and (r.type == "agent.progress" or r.type == "agent.input_required" or r.type == "telemetry.warning") then
      latest[r.task_id] = latest[r.task_id] or {}
      table.insert(latest[r.task_id], 1, r)
      if #latest[r.task_id] > limits.activity_per_task then table.remove(latest[r.task_id]) end
    end
  end
  local items = {}
  local order = { failed = 1, cancelled = 2, running = 3, queued = 4, succeeded = 5 }
  for _, t in ipairs(snap.tasks) do
    local item = { id = t.id, state = t.state, display = t.display, title = t.title, rank = order[t.state] or 9 }
    if t.state == "failed" then
      item.text = ("%s failed: %s"):format(t.id, (t.outcome and t.outcome.reason) or "unknown")
      item.ref = t.outcome and t.outcome.attempt_id
      local dependents = {}
      for _, o in ipairs(snap.tasks) do if o.state == "queued" and o.blockers then for _, b in ipairs(o.blockers) do if b.id == t.id then dependents[#dependents + 1] = o.id end end end end
      if #dependents > 0 then item.text = item.text .. "; blocks " .. table.concat(dependents, ", ") end
    elseif t.state == "queued" and t.blockers and #t.blockers > 0 then
      item.text = ("%s blocked: %s"):format(t.id, t.blockers[1].text); item.rank = 2.5
    elseif t.state == "running" then
      local l = latest[t.id] and latest[t.id][1]
      item.text = ("%s %s%s"):format(t.id, (t.display or "running"):lower(), l and l.payload and l.payload.message and (": " .. l.payload.message) or "")
      item.ref = l and l.event_id or t.current_attempt_id
    elseif t.state == "queued" then item.text = t.id .. " queued"
    else item.text = ("%s %s"):format(t.id, t.state) end
    items[#items + 1] = item
  end
  table.sort(items, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.id < b.id end)
  local lines, refs, chars, truncated = {}, {}, 0, 0
  for i, it in ipairs(items) do
    if i > limits.tasks or chars + #it.text > limits.chars then truncated = truncated + 1
    else lines[#lines + 1] = it.text; chars = chars + #it.text + 2; if it.ref then refs[#refs + 1] = { task = it.id, ref = it.ref } end end
  end
  local text = table.concat(lines, "; ")
  if truncated > 0 then text = text .. ("; … %d more task(s) omitted (limit %d tasks/%d chars)"):format(truncated, limits.tasks, limits.chars) end
  return { text = text, items = #items, shown = #lines, truncated = truncated, refs = refs, control_seq = snap.control_seq, generated_at = snap.generated_at }
end

return M
