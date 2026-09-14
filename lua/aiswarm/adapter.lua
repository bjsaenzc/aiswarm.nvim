-- Adapt legacy snapshots/events (v2 shape, also served for v3 boards by the compat CLI) into the
-- normalized store model with explicit capabilities (SDD-045).
local P = require("aiswarm.protocol")
local M = {}

local V2_STATE = { ready = "queued", active = "running", done = "succeeded", failed = "failed" }

--- Normalize one task from the v2 read shape.
function M.normalize_task(t, all, v3)
  local task = {
    id = t.id, title = t.title or "", provider = t.provider or "?", depends_on = t.depends_on or {}, priority = t.priority or 50,
    timeout = t.timeout, isolation = t.isolation or (t.worktree and "worktree" or "shared"), created_at = t.created_at or t.created,
    updated_at = t.updated_at or t.ended_at or t.started_at or t.created, revision = t.revision, legacy = not v3,
    current_attempt_id = t.current_attempt_id, attempts = t.attempts or {}, health = t.health, elapsed_s = t.elapsed_s, duration_s = t.duration_s,
    session = t.session, cwd = t.dir, prompt_path = t.prompt, cost_usd = t.cost_usd, live = t.live, last_progress = t.last_progress,
  }
  if v3 and P.TASK_STATES[t.v3_state or ""] then task.state = t.v3_state
  elseif v3 and P.TASK_STATES[t.state] then task.state = t.state
  else task.state = V2_STATE[t.state] or "failed" end
  if t.state == "failed" and t.rc == "orphaned" then task.outcome = { reason = "orphaned", finished_at = t.ended_at }
  elseif task.state ~= "queued" and task.state ~= "running" then
    task.outcome = t.outcome or { exit_code = type(t.rc) == "number" and t.rc or nil, finished_at = t.ended_at, duration_s = t.duration_s, report = t.report }
  end
  if t.outcome then task.outcome = t.outcome end
  return task
end

--- Normalize a v2/compat snapshot ({tasks=list|map, counts, seq, paused, ...}).
function M.normalize_snapshot(meta, tasks_map)
  local v3 = meta.v3 == true or (meta.api_version or 0) >= 3
  local list = {}
  local src = tasks_map or meta.tasks or {}
  if not vim.islist(src) then local arr = {}; for _, t in pairs(src) do arr[#arr + 1] = t end; src = arr end
  local by_id = {}
  for _, t in ipairs(src) do local n = M.normalize_task(t, nil, v3); list[#list + 1] = n; by_id[n.id] = n end
  local health_opts = { quiet_after_s = require("aiswarm").config.ui.quiet_after_s }
  for _, task in ipairs(list) do
    if task.state == "queued" then task.blockers = task.blockers or P.blockers(task, by_id) end
    task.display, task.display_detail = P.display_state(task, task.current_attempt_id and { state = "running", phase = task.health and task.health.phase } or (task.state == "running" and { state = "running" } or nil), task.health, health_opts)
    if v3 and src and task.display == nil then task.display = "?" end
  end
  local scheduler = meta.scheduler and vim.deepcopy(meta.scheduler) or { state = "unknown", paused = meta.paused == true, wip = meta.wip, tick_s = meta.tick, legacy = true }
  if not meta.scheduler then scheduler.state = meta.session_live and "running" or "unknown" end
  local caps = v3 and vim.tbl_extend("force", { attempts = true, cancel = true, retry = true, telemetry = true }, meta.capabilities or {})
    or { attempts = false, cancel = false, retry = false, telemetry = false, legacy = true, atomic_add = (meta.capabilities or {}).atomic_add == true }
  return { tasks = list, attempts = meta.attempts or {}, scheduler = scheduler, seq = meta.seq,
    board = { root = meta.root, board_id = meta.board_id, schema = v3 and "v3" or "v2", api_version = meta.api_version }, capabilities = caps }
end

--- Normalize a v2 event line into a control event and/or an activity record.
function M.normalize_event(e, root_id)
  local ev = { event_id = ("v2:%s:%s"):format(root_id or "", tostring(e.seq)), seq = e.seq, type = e.v3_type or ("v2." .. tostring(e.type)), task_id = e.task ~= "" and e.task or nil,
    attempt_id = e.attempt, ts = e.ts, needs_refresh = true }
  local lifecycle = { queued = true, started = true, done = true, failed = true, cancelled = true, dispatched = true, edited = true, reordered = true, paused = true, resumed = true }
  local activity
  if e.type == "progress" or e.type == "message" then
    activity = { event_id = ev.event_id .. ":a", ts = e.ts, task_id = ev.task_id, kind = e.type, level = "info", text = e.note or e.text or e.type, source = e.actor or "legacy", provenance = "worker_report" }
    ev.needs_refresh = false
  elseif lifecycle[e.type] then
    local level = (e.type == "failed") and "error" or "info"
    local text = e.type
    if e.type == "failed" and e.rc == "orphaned" then text = "failed (orphaned)" end
    if e.title then text = text .. " · " .. e.title end
    activity = { event_id = ev.event_id .. ":a", ts = e.ts, task_id = ev.task_id, kind = "lifecycle", level = level, text = text, source = e.actor or "backend", provenance = "backend" }
  end
  return ev, activity
end

--- Attach the legacy state engine to the store. Returns an unsubscribe function.
function M.attach(store, legacy)
  local root_id = require("aiswarm").root()
  local initial = true
  return legacy.subscribe(function(kind, payload)
    if kind == "refresh" then
      if payload and payload.seq ~= nil then
        local ok, err = store.apply_snapshot(M.normalize_snapshot(payload, legacy.tasks))
        if not ok then store.set_connection({ state = "incompatible", error = err }) end
        initial = false
      elseif payload and next(payload) == nil then
        store.reset(); store.set_connection({ state = "connecting" })
      end
    elseif kind == "event" then
      local ev, activity = M.normalize_event(payload, root_id)
      if activity and not initial then store.apply_activity(activity) end
      store.apply_control(ev)
    elseif kind == "error" then
      store.set_connection({ state = "offline", error = payload, age_s = store.connection.last_success and math.floor((vim.uv.now() - store.connection.last_success) / 1000) or nil })
    end
  end)
end

return M
