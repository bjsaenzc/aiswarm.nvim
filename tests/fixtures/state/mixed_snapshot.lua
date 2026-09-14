-- Deterministic mixed-state fixture used by workspace tests (normalized store shape).
local M = {}
function M.snapshot(n)
  n = n or 12
  local tasks, attempts = {}, {}
  local states = { "running", "queued", "succeeded", "failed", "cancelled", "queued" }
  for i = 1, n do
    local id = ("T-%03d"):format(i)
    local state = states[(i - 1) % #states + 1]
    local t = { id = id, title = ("Task %d %s"):format(i, i % 4 == 0 and "日本語 タイトル 🚀" or "plain title"), provider = (i % 2 == 0) and "mock" or "claude",
      depends_on = (i % 6 == 0) and { ("T-%03d"):format(i - 1) } or {}, priority = (i * 7) % 100, timeout = 1800, isolation = "shared",
      created_at = ("2026-09-14T00:%02d:00.000Z"):format(i % 60), updated_at = ("2026-09-14T01:%02d:00.000Z"):format(i % 60), revision = 1, state = state, attempts = {} }
    if state == "running" or state == "succeeded" or state == "failed" or state == "cancelled" then
      local aid = ("00000000-0000-4000-8000-%012d"):format(i)
      t.attempts, t.current_attempt_id = { aid }, aid
      attempts[#attempts + 1] = { attempt_id = aid, task_id = id, ordinal = 1, provider = t.provider, state = state == "running" and "running" or state,
        started_at = t.created_at, finished_at = state ~= "running" and t.updated_at or nil, reason = state == "failed" and "exit 1" or nil,
        paths = { dir = "/fixture/" .. aid, stdout = "/fixture/" .. aid .. "/stdout.log", report = "/fixture/" .. aid .. "/report.md" },
        report = { status = state == "succeeded" and "complete" or "missing" }, config = { cwd = "/fixture/project", timeout = 1800, isolation = "shared" } }
      if state ~= "running" then t.outcome = { attempt_id = aid, finished_at = t.updated_at, reason = state == "failed" and "exit 1" or nil, exit_code = state == "failed" and 1 or 0, report = state == "succeeded" and "complete" or "missing" } end
    end
    tasks[#tasks + 1] = t
  end
  local P = require("aiswarm.protocol")
  local by = {}; for _, t in ipairs(tasks) do by[t.id] = t end
  for _, t in ipairs(tasks) do
    if t.state == "queued" then t.blockers = P.blockers(t, by) end
    t.display, t.display_detail = P.display_state(t, t.current_attempt_id and { state = "running" } or nil, nil, {})
  end
  return { tasks = tasks, attempts = attempts, scheduler = { state = "running", wip = 3, paused = false }, seq = 42,
    board = { root = "/fixture/project/.aiswarm", board_id = "57fc3ea0-6b8f-45c2-8e8f-3a5f98cc4ed3", schema = "v3" },
    capabilities = { attempts = true, cancel = true, retry = true, telemetry = true } }
end
return M
