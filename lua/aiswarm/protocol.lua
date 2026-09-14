-- Shared schemas and validators for board/task/attempt/control/telemetry records (SDD-017).
-- Pure Lua: no I/O, usable from the editor and the headless runtime alike.
local P = {}

P.SCHEMA_VERSION = 1         -- record envelope version
P.BOARD_SCHEMA = 3           -- board.json schema_version
P.LIMITS = { id = 64, title = 200, message = 4096, phase = 64, preview = 512, record_bytes = 65536, deps = 64,
             consumer = 64, timeout = 7 * 24 * 3600, priority = 1000000000 }
P.TASK_STATES = { queued = true, running = true, succeeded = true, failed = true, cancelled = true }
P.ATTEMPT_STATES = { starting = true, running = true, succeeded = true, failed = true, cancelled = true }
P.TERMINAL = { succeeded = true, failed = true, cancelled = true }
P.ISOLATION = { shared = true, worktree = true }
P.CONTROL_TYPES = {
  ["board.initialized"] = true, ["board.migrated"] = true, ["task.queued"] = true, ["task.edited"] = true,
  ["task.reordered"] = true, ["task.cancelled"] = true, ["task.retried"] = true, ["task.imported"] = true, ["task.finished"] = true,
  ["attempt.reserved"] = true, ["attempt.started"] = true, ["attempt.finished"] = true, ["scheduler.changed"] = true,
}
P.TELEMETRY_TYPES = {
  ["agent.heartbeat"] = true, ["agent.progress"] = true, ["agent.tool.started"] = true, ["agent.tool.finished"] = true,
  ["agent.input_required"] = true, ["agent.output"] = true, ["agent.artifact"] = true, ["agent.usage"] = true,
  ["telemetry.warning"] = true, ["stream.gap"] = true, ["stream.status"] = true,
}
-- Envelope keys a payload may never override.
P.RESERVED = { schema_version = true, board_id = true, journal_generation = true, control_seq = true, event_id = true,
  txn = true, observed_at = true, type = true, task_id = true, attempt_id = true, actor = true, source = true,
  stream_generation = true, attempt_seq = true, level = true, payload = true }
P.LEVELS = { debug = true, info = true, warn = true, error = true }

-- ---------------------------------------------------------------- primitives
function P.valid_task_id(id)
  return type(id) == "string" and #id >= 1 and #id <= P.LIMITS.id and id:match("^[%w][%w_%-]*$") ~= nil
end
function P.valid_uuid(s)
  return type(s) == "string" and s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end
function P.valid_consumer(s)
  return type(s) == "string" and #s <= P.LIMITS.consumer and s:match("^[%w][%w_%.%-]*$") ~= nil
end
local function is_int(v, min, max)
  return type(v) == "number" and v % 1 == 0 and (min == nil or v >= min) and (max == nil or v <= max)
end
P.is_int = is_int
function P.valid_iso(s) return type(s) == "string" and s:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d") ~= nil end

--- Sort order of the ready queue: numeric priority, creation time, id.
function P.compare_queue(a, b)
  local pa, pb = a.priority or 50, b.priority or 50
  if pa ~= pb then return pa < pb end
  if (a.created_at or "") ~= (b.created_at or "") then return (a.created_at or "") < (b.created_at or "") end
  return a.id < b.id
end

-- ---------------------------------------------------------------- task fields
--- Validate and normalize mutable task fields. `opts.partial` allows missing fields (edit).
---@return table? normalized, string? err, string? field
function P.check_task_fields(f, opts)
  opts = opts or {}
  local out = {}
  local function need(k) return not opts.partial or f[k] ~= nil end
  if need("title") then
    local title = f.title
    if title == nil then title = "" end
    if type(title) ~= "string" then return nil, "title must be a string", "title" end
    if #title > P.LIMITS.title then return nil, ("title exceeds %d bytes"):format(P.LIMITS.title), "title" end
    if title:find("[%c]") then return nil, "title must not contain control characters", "title" end
    out.title = title
  end
  if need("provider") then
    if type(f.provider) ~= "string" or f.provider == "" then return nil, "provider is required", "provider" end
    if opts.providers and not opts.providers[f.provider] then return nil, "unknown provider: " .. f.provider, "provider" end
    out.provider = f.provider
  end
  if need("priority") then
    local v = f.priority
    if v == nil then v = 50 end
    if type(v) == "string" and v:match("^%d+$") then v = tonumber(v) end
    if not is_int(v, 0, P.LIMITS.priority) then return nil, "priority must be a non-negative integer", "priority" end
    out.priority = v
  end
  if need("timeout") then
    local v = f.timeout
    if v == nil then v = 1800 end
    if type(v) == "string" and v:match("^%d+$") then v = tonumber(v) end
    if not is_int(v, 1, P.LIMITS.timeout) then return nil, "timeout must be a positive integer (seconds)", "timeout" end
    out.timeout = v
  end
  if need("isolation") then
    local v = f.isolation
    if v == nil then v = "shared" end
    if v == true then v = "worktree" elseif v == false then v = "shared" end
    if not P.ISOLATION[v] then return nil, "isolation must be shared or worktree", "isolation" end
    out.isolation = v
  end
  if need("depends_on") then
    local deps = f.depends_on
    if deps == nil then deps = {} end
    if type(deps) == "string" then
      local list = {}
      for d in deps:gmatch("[^,%s]+") do list[#list + 1] = d end
      deps = list
    end
    if type(deps) ~= "table" or not vim.islist(deps) then return nil, "depends_on must be a list", "depends_on" end
    if #deps > P.LIMITS.deps then return nil, "too many dependencies", "depends_on" end
    local seen, list = {}, {}
    for _, d in ipairs(deps) do
      if not P.valid_task_id(d) then return nil, "invalid dependency id: " .. tostring(d), "depends_on" end
      if f.id and d == f.id then return nil, "a task cannot depend on itself", "depends_on" end
      if not seen[d] then seen[d] = true; list[#list + 1] = d end
    end
    out.depends_on = list
  end
  return out
end

--- Dependency graph check: every dep exists, no cycles (including the proposed edges).
---@param id string task being created/edited
---@param deps string[]
---@param tasks table<string, table>
---@return boolean ok, string? err
function P.check_dependency_graph(id, deps, tasks)
  for _, d in ipairs(deps) do
    if d == id then return false, "a task cannot depend on itself" end
    if not tasks[d] then return false, "unknown dependency: " .. d end
  end
  -- DFS from each dep following depends_on; reaching `id` is a cycle
  local visiting, done = {}, {}
  local function visit(n, path)
    if n == id then return false, "dependency cycle: " .. table.concat(path, " -> ") .. " -> " .. id end
    if done[n] then return true end
    if visiting[n] then return true end
    visiting[n] = true
    local t = tasks[n]
    for _, d in ipairs(t and t.depends_on or {}) do
      path[#path + 1] = n
      local ok, err = visit(d, path)
      path[#path] = nil
      if not ok then return false, err end
    end
    visiting[n], done[n] = nil, true
    return true
  end
  for _, d in ipairs(deps) do
    local ok, err = visit(d, { id })
    if not ok then return false, err end
  end
  return true
end

--- Unsatisfied dependencies of a queued task, with the exact reason.
---@return table[] blockers  { {id, reason, text} }
function P.blockers(task, tasks)
  local out = {}
  for _, d in ipairs(task.depends_on or {}) do
    local dep = tasks[d]
    if not dep then out[#out + 1] = { id = d, reason = "missing", text = "missing dependency " .. d }
    elseif dep.state == "failed" then out[#out + 1] = { id = d, reason = "failed", text = "blocked by " .. d .. " (failed)" }
    elseif dep.state == "cancelled" then out[#out + 1] = { id = d, reason = "cancelled", text = "blocked by " .. d .. " (cancelled)" }
    elseif dep.state ~= "succeeded" then out[#out + 1] = { id = d, reason = dep.state, text = "waiting for " .. d .. " (" .. dep.state .. ")" }
    end
  end
  return out
end

-- ---------------------------------------------------------------- records
function P.validate_task(t)
  if type(t) ~= "table" then return false, "task must be an object" end
  if not P.valid_task_id(t.id) then return false, "invalid task id" end
  if not P.TASK_STATES[t.state] then return false, "invalid task state: " .. tostring(t.state) end
  if not is_int(t.revision, 1) then return false, "revision must be a positive integer" end
  if not is_int(t.prompt_revision, 1) then return false, "prompt_revision must be a positive integer" end
  local _, err, field = P.check_task_fields(t, {})
  if err then return false, err, field end
  if t.current_attempt_id ~= nil and not P.valid_uuid(t.current_attempt_id) then return false, "invalid current_attempt_id" end
  if type(t.attempts) ~= "table" then return false, "attempts must be a list" end
  if not P.valid_iso(t.created_at) then return false, "created_at must be an ISO timestamp" end
  return true
end

function P.validate_attempt(a)
  if type(a) ~= "table" then return false, "attempt must be an object" end
  if not P.valid_uuid(a.attempt_id) then return false, "invalid attempt_id" end
  if not P.valid_task_id(a.task_id) then return false, "invalid task_id" end
  if not is_int(a.ordinal, 1) then return false, "ordinal must be a positive integer" end
  if not P.ATTEMPT_STATES[a.state] then return false, "invalid attempt state: " .. tostring(a.state) end
  if type(a.config) ~= "table" then return false, "config must be an object" end
  if type(a.paths) ~= "table" then return false, "paths must be an object" end
  return true
end

function P.validate_scheduler(s)
  if type(s) ~= "table" then return false, "scheduler must be an object" end
  if s.state ~= "running" and s.state ~= "stopped" then return false, "scheduler state must be running or stopped" end
  if s.wip ~= nil and not is_int(s.wip, 1, 1000) then return false, "wip must be an integer in 1..1000" end
  if s.paused ~= nil and type(s.paused) ~= "boolean" then return false, "paused must be a boolean" end
  return true
end

local function check_payload_keys(payload)
  if type(payload) ~= "table" then return false, "payload must be an object" end
  for k in pairs(payload) do if P.RESERVED[k] then return false, "payload overrides reserved key: " .. k end end
  return true
end

--- Validate a control record envelope and its typed payload.
function P.validate_control_record(r)
  if type(r) ~= "table" then return false, "record must be an object" end
  if not is_int(r.schema_version, 1) then return false, "schema_version must be an integer" end
  if r.schema_version > P.SCHEMA_VERSION then return false, "unsupported schema_version " .. r.schema_version, "incompatible" end
  if not P.valid_uuid(r.board_id) then return false, "invalid board_id" end
  if not is_int(r.journal_generation, 1) then return false, "journal_generation must be a positive integer" end
  if not is_int(r.control_seq, 1) then return false, "control_seq must be a positive integer" end
  if type(r.event_id) ~= "string" or r.event_id == "" then return false, "event_id required" end
  if not P.valid_iso(r.observed_at) then return false, "observed_at must be an ISO timestamp" end
  if type(r.type) ~= "string" then return false, "type required" end
  if r.task_id ~= nil and not P.valid_task_id(r.task_id) then return false, "invalid task_id" end
  if r.attempt_id ~= nil and not P.valid_uuid(r.attempt_id) then return false, "invalid attempt_id" end
  local ok, err = check_payload_keys(r.payload)
  if not ok then return false, err end
  if r.txn ~= nil then
    if type(r.txn) ~= "table" or not is_int(r.txn.index, 1) or not is_int(r.txn.count, 1) or type(r.txn.last) ~= "boolean" then
      return false, "txn must carry index/count/last"
    end
  end
  if P.CONTROL_TYPES[r.type] then
    if r.type:match("^task%.") and r.type ~= "task.imported" then
      local tok, terr = P.validate_task(r.payload.task); if not tok then return false, "payload.task: " .. terr end
    end
    if r.type:match("^attempt%.") then
      local aok, aerr = P.validate_attempt(r.payload.attempt); if not aok then return false, "payload.attempt: " .. aerr end
    end
    if r.type == "scheduler.changed" then
      local sok, serr = P.validate_scheduler(r.payload.scheduler); if not sok then return false, "payload.scheduler: " .. serr end
    end
  end
  -- unknown control types are accepted for inspection; the reducer ignores them
  return true
end

--- Validate a telemetry record envelope.
function P.validate_telemetry_record(r)
  if type(r) ~= "table" then return false, "record must be an object" end
  if not is_int(r.schema_version, 1) then return false, "schema_version must be an integer" end
  if r.schema_version > P.SCHEMA_VERSION then return false, "unsupported schema_version " .. r.schema_version, "incompatible" end
  if not P.valid_uuid(r.board_id) then return false, "invalid board_id" end
  if not P.valid_task_id(r.task_id) then return false, "invalid task_id" end
  if not P.valid_uuid(r.attempt_id) then return false, "invalid attempt_id" end
  if type(r.source) ~= "string" or r.source == "" then return false, "source required" end
  if type(r.stream_generation) ~= "string" then return false, "stream_generation must be a string" end
  if not is_int(r.attempt_seq, 0) then return false, "attempt_seq must be a non-negative integer" end
  if type(r.event_id) ~= "string" then return false, "event_id required" end
  if not P.valid_iso(r.observed_at) then return false, "observed_at must be an ISO timestamp" end
  if type(r.type) ~= "string" then return false, "type required" end
  if r.level ~= nil and not P.LEVELS[r.level] then return false, "invalid level" end
  local ok, err = check_payload_keys(r.payload)
  if not ok then return false, err end
  local p = r.payload
  if r.type == "agent.progress" then
    if p.message ~= nil and (type(p.message) ~= "string" or #p.message > P.LIMITS.message) then return false, "progress message too long or not a string" end
    if p.phase ~= nil and (type(p.phase) ~= "string" or #p.phase > P.LIMITS.phase) then return false, "invalid phase" end
    if p.completed ~= nil and not is_int(p.completed, 0) then return false, "completed must be an integer" end
    if p.total ~= nil and not is_int(p.total, 0) then return false, "total must be an integer" end
  elseif r.type == "agent.output" then
    if p.stream ~= "stdout" and p.stream ~= "stderr" then return false, "output stream must be stdout or stderr" end
    if not is_int(p.offset, 0) or not is_int(p.bytes, 0) or not is_int(p.segment, 1) then return false, "output offset/bytes/segment must be integers" end
  elseif r.type == "agent.input_required" then
    if type(p.request_id) ~= "string" or type(p.actions) ~= "table" then return false, "input_required needs request_id and actions" end
  end
  return true
end

--- Validate an inbox message (explicit worker update) before the writer accepts it.
function P.validate_inbox(m)
  if type(m) ~= "table" then return false, "message must be an object" end
  if not P.valid_uuid(m.board_id) or not P.valid_task_id(m.task_id) or not P.valid_uuid(m.attempt_id) then return false, "message must carry board/task/attempt identity" end
  if m.type ~= "agent.progress" and m.type ~= "agent.artifact" and m.type ~= "agent.usage" then return false, "unsupported inbox type: " .. tostring(m.type) end
  if type(m.message_id) ~= "string" or m.message_id == "" then return false, "message_id required" end
  local ok, err = check_payload_keys(m.payload)
  if not ok then return false, err end
  return true
end

--- Decoded cursor structure check (encoding lives in runtime/cursor.lua).
function P.validate_cursor(c)
  if type(c) ~= "table" or c.v ~= 1 then return false, "unsupported cursor version" end
  if not P.valid_uuid(c.board) then return false, "cursor board invalid" end
  if type(c.control) ~= "table" or not is_int(c.control.g, 0) or not is_int(c.control.seq, 0) then return false, "cursor control position invalid" end
  if c.attempts ~= nil then
    if type(c.attempts) ~= "table" then return false, "cursor attempts invalid" end
    for id, pos in pairs(c.attempts) do
      if not P.valid_uuid(id) or type(pos) ~= "table" or type(pos.g) ~= "string" or not is_int(pos.seq, 0) then return false, "cursor attempt position invalid" end
    end
  end
  return true
end

--- Legacy (v2) state name for a v3 task.
function P.v2_state(task)
  if task.state == "queued" then return "ready" end
  if task.state == "running" then return "active" end
  if task.state == "succeeded" then return "done" end
  return "failed"
end

--- Human display state for a task given its current attempt and health inputs.
---@param opts { now_s: number, quiet_after_s?: number, heartbeat_ms?: number }
function P.display_state(task, attempt, health, opts)
  opts = opts or {}
  if task.state == "queued" then
    local b = task.blockers
    if b and #b > 0 then return "Blocked", b[1].text end
    return "Queued", nil
  elseif task.state == "running" then
    if not attempt or attempt.state == "starting" then return "Starting", nil end
    if health and health.input_required then return "Waiting for input", health.input_required end
    if health and health.stale then return "Telemetry stale", "no heartbeat for " .. tostring(health.stale_for_s) .. "s" end
    if health and health.quiet then return "Quiet", "no output for " .. tostring(health.quiet_for_s) .. "s" end
    return "Running", attempt.phase
  elseif task.state == "succeeded" then return "Succeeded", nil
  elseif task.state == "failed" then
    local reason = task.outcome and task.outcome.reason
    if reason == "orphaned" then return "Failed: orphaned", "worker process died without a terminal event" end
    return "Failed", reason
  elseif task.state == "cancelled" then return "Cancelled", nil end
  return task.state, nil
end

return P
