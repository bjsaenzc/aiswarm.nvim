-- v2-shaped reads and legacy mutations over v3 boards (SDD-037).
local U = require("aiswarm.runtime.util")
local P = require("aiswarm.protocol")
local M = {}

function M.v2_task(t, attempts, ctx)
  local cur = t.current_attempt_id and vim.tbl_filter(function(a) return a.attempt_id == t.current_attempt_id end, attempts or {})[1] or nil
  local last = cur
  if not last and attempts and #attempts > 0 then last = attempts[#attempts] end
  local started = last and last.started_at or nil
  local out = {
    id = t.id, title = t.title, provider = t.provider, mode = "headless", timeout = t.timeout, worktree = t.isolation == "worktree",
    prompt = t.prompt_path, depends_on = t.depends_on, created = t.created_at, priority = t.priority, state = P.v2_state(t),
    started_at = started, ended_at = t.outcome and t.outcome.finished_at or nil,
    duration_s = t.outcome and t.outcome.duration_s or nil, rc = t.outcome and (t.outcome.reason == "orphaned" and "orphaned" or t.outcome.exit_code) or nil,
    cost_usd = last and last.usage and last.usage.cost_usd or nil, session = last and last.tmux and last.tmux.session or nil,
    dir = last and last.config and last.config.cwd or nil, live = t.state == "running",
    revision = t.revision, current_attempt_id = t.current_attempt_id, display = t.display, display_detail = t.display_detail, blockers = t.blockers,
    health = t.health, attempts = t.attempts, isolation = t.isolation, outcome = t.outcome, created_at = t.created_at, updated_at = t.updated_at,
    v3_state = t.state,
    api_version = 3,
  }
  if t.state == "running" and started then out.elapsed_s = math.floor(U.now_s() - (U.parse_iso(started) or U.now_s())) end
  if ctx and last then
    out.result_path, out.log_path = last.paths.report, last.paths.stdout
    if ctx.with_result then out.result = U.read(last.paths.report) end
  end
  return out
end

function M.v2_snapshot(snap)
  local tasks, counts = {}, { ready = 0, active = 0, done = 0, failed = 0 }
  local by_task = {}
  for _, a in ipairs(snap.attempts) do by_task[a.task_id] = by_task[a.task_id] or {}; table.insert(by_task[a.task_id], a) end
  for _, t in ipairs(snap.tasks) do
    local v = M.v2_task(t, by_task[t.id]); tasks[#tasks + 1] = v; counts[v.state] = counts[v.state] + 1
  end
  return { api_version = 2, v3 = true, capabilities = { atomic_add = true, attempts = true, cancel = true, retry = true, telemetry = true },
    root = snap.root, session = "aiswarm", wip = snap.scheduler.wip, tick = snap.scheduler.tick_s, seq = snap.control_seq,
    paused = snap.scheduler.paused == true, scheduler = snap.scheduler, counts = counts, tasks = tasks, board_id = snap.board_id, attempts = snap.attempts }
end

function M.render_status(snap)
  local lines = { ("  aiswarm  %s  scheduler %s%s  wip %s"):format(snap.root, snap.scheduler.state or "?", snap.scheduler.paused and " (paused)" or "", tostring(snap.scheduler.wip)) }
  lines[#lines + 1] = ("  %-10s %-8s %-8s %-18s %s"):format("STATE", "ID", "PROVIDER", "DISPLAY", "TITLE")
  for _, t in ipairs(snap.tasks) do
    lines[#lines + 1] = ("  %-10s %-8s %-8s %-18s %s"):format(t.state, t.id, t.provider, t.display or "", (t.title or ""):sub(1, 48))
  end
  return table.concat(lines, "\n") .. "\n"
end

--- Map a control record to a v2 event line (for `events` and the legacy follower).
local V2 = { ["task.queued"] = "queued", ["task.edited"] = "edited", ["task.reordered"] = "reordered", ["task.cancelled"] = "cancelled",
  ["task.retried"] = "queued", ["attempt.reserved"] = "dispatched", ["attempt.started"] = "started", ["task.finished"] = nil, ["scheduler.changed"] = nil }
function M.v2_event(rec)
  local t = V2[rec.type]
  local p = rec.payload or {}
  if rec.type == "task.finished" then t = p.task and (p.task.state == "succeeded" and "done" or "failed") end
  if rec.type == "scheduler.changed" then
    local s = p.scheduler or {}
    if s.paused == true then t = "paused" elseif s.paused == false and vim.tbl_contains(p.changed or {}, "paused") then t = "resumed" else t = "scheduler" end
  end
  if rec.type == "attempt.finished" then return nil end
  if not t then t = rec.type end
  local e = { seq = rec.control_seq, ts = rec.observed_at, type = t, task = rec.task_id or "", actor = rec.actor, v3_type = rec.type, attempt = rec.attempt_id }
  if p.task then e.title, e.provider, e.revision = p.task.title, p.task.provider, p.task.revision end
  if p.task and p.task.outcome then e.rc, e.duration_s = p.task.outcome.exit_code, p.task.outcome.duration_s end
  return e
end

function M.register(C)
  local B = require("aiswarm.runtime.board")
  local J = require("aiswarm.runtime.journal")
  local O = require("aiswarm.runtime.ops")
  local fail = B.fail
  C.table.events = { bools = { follow = true, f = true }, run = function(a)
    local ctx = B.load(a.root)
    local since = tonumber(a.opts.since or 0) or 0
    local out = io.stdout
    local offset = J.each(ctx.root, function(rec)
      if rec.control_seq > since then local e = M.v2_event(rec); if e then out:write(vim.json.encode(e), "\n") end end
    end)
    out:flush()
    if not (a.opts.follow or a.opts.f) then return nil end
    -- follow: poll the journal for appends (v3 editors use `stream`; this keeps the legacy follower working)
    while true do
      vim.uv.sleep(250)
      offset = J.each(ctx.root, function(rec)
        if rec.control_seq > since then local e = M.v2_event(rec); if e then out:write(vim.json.encode(e), "\n") end end
      end, offset)
      out:flush()
    end
  end }
  C.table.kill = { run = function(a)
    local ctx = B.load(a.root)
    local id = a.pos[1]; if not id then fail(1, "usage: kill <id>") end
    io.stderr:write("aiswarm: `kill` keeps its legacy meaning (cancel and requeue); use `cancel` for a permanent cancellation\n")
    local r = require("aiswarm.runtime.lifecycle").kill_requeue(ctx, id)
    if a.json then return r end
    return ("cancelled and requeued %s"):format(id)
  end }
  C.table.pause = { run = function(a)
    local ctx = B.load(a.root); O.scheduler_changed(ctx, { paused = true }); return "scheduler paused"
  end }
  C.table.resume = { run = function(a)
    local ctx = B.load(a.root); O.scheduler_changed(ctx, { paused = false }); return "scheduler resumed"
  end }
  C.table.tail = { bools = { follow = true, f = true }, run = function(a)
    local ctx = B.load(a.root)
    local id = a.pos[1]; if not id then fail(1, "usage: tail <id> [-n N] [-f]") end
    local st = B.read_state(ctx)
    local task = st.tasks[id] or fail(2, "no such task: " .. id)
    local aid = task.current_attempt_id or task.attempts[#task.attempts]
    if not aid then fail(2, "no attempt for " .. id) end
    local att = st.attempts[aid]
    local n = tonumber(a.opts.n) or 200
    local text = U.read(att.paths.stdout) or ""
    local lines = vim.split(text, "\n", { trimempty = false })
    if lines[#lines] == "" then table.remove(lines) end
    local start = math.max(1, #lines - n + 1)
    local out = {}
    for i = start, #lines do out[#out + 1] = lines[i] end
    if a.opts.follow or a.opts.f then
      io.stdout:write(table.concat(out, "\n") .. (#out > 0 and "\n" or "")); io.stdout:flush()
      local offset = #text
      while true do
        vim.uv.sleep(200)
        local stt = vim.uv.fs_stat(att.paths.stdout)
        if stt and stt.size > offset then
          local fd = vim.uv.fs_open(att.paths.stdout, "r", 292); local data = vim.uv.fs_read(fd, stt.size - offset, offset); vim.uv.fs_close(fd)
          offset = stt.size; io.stdout:write(data); io.stdout:flush()
        end
      end
    end
    return table.concat(out, "\n") .. "\n"
  end }
  C.table.go = { run = function(a) return C.table.attach.run(a) end }
  C.table.up = { run = function(a) a.pos = { "start" }; return C.table.scheduler.run(a) end }
  C.table.loop = { run = function(a) a.pos = { "loop" }; return C.table.scheduler.run(a) end }
  C.table.progress = C.table.progress or { run = function(a)
    -- legacy form: progress <task-id> [note]; canonical form registered by telemetry_commands
    fail(4, "progress requires the telemetry runtime")
  end }
end

return M
