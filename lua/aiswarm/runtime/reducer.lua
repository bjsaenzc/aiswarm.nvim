-- Pure control reducer: control records carry post-state, so application is idempotent (SDD-021).
local R = {}

--- Apply one record to `state` ({tasks, attempts, scheduler, board}). Returns touched keys.
function R.apply(state, rec)
  local p, touched = rec.payload or {}, {}
  if type(p.task) == "table" and p.task.id then state.tasks[p.task.id] = p.task; touched[#touched + 1] = "task:" .. p.task.id end
  if type(p.tasks) == "table" then for _, t in ipairs(p.tasks) do state.tasks[t.id] = t; touched[#touched + 1] = "task:" .. t.id end end
  if type(p.attempt) == "table" and p.attempt.attempt_id then state.attempts[p.attempt.attempt_id] = p.attempt; touched[#touched + 1] = "attempt:" .. p.attempt.attempt_id end
  if type(p.scheduler) == "table" then state.scheduler = p.scheduler; touched[#touched + 1] = "scheduler" end
  if type(p.board) == "table" then state.board = vim.tbl_extend("force", state.board or {}, p.board); touched[#touched + 1] = "board" end
  -- unknown types / payloads change nothing
  return touched
end

function R.replay(state, records)
  local touched = {}
  for _, rec in ipairs(records) do for _, k in ipairs(R.apply(state, rec)) do touched[k] = true end end
  return touched
end

return R
