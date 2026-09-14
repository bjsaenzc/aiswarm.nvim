-- Normalized editor state store (SDD-046): validated snapshots/control events, task/attempt
-- lookup, cached selectors, isolated subscriptions and bounded activity. No I/O.
local P = require("aiswarm.protocol")
local S = {}

S.LIMITS = { activity_records = 2000, activity_bytes = 4 * 1024 * 1024, per_attempt = 500, seen_events = 5000 }
S.stats = { snapshots = 0, events = 0, duplicates = 0, dropped_activity = 0, subscriber_errors = 0 }

--- Replace the contents of `dst` with `src` without changing the table's identity: engines hand out
--- `store.tasks` directly (LuaJIT honours no `__pairs`, so a proxy cannot be iterated).
local function replace_into(dst, src)
  for k in pairs(dst) do dst[k] = nil end
  for k, v in pairs(src) do dst[k] = v end
  return dst
end

function S.reset()
  S.version = 0
  S.tasks, S.attempts = replace_into(S.tasks or {}, {}), replace_into(S.attempts or {}, {})
  S.scheduler, S.board = { state = "unknown" }, { capabilities = {}, schema = "unknown" }
  S.connection = { state = "connecting", last_success = nil, error = nil, retry_at = nil, age_s = nil }
  S.seq = 0
  S.activity = { records = {}, bytes = 0, per_attempt = {}, seq = 0 }
  S.attention = {}   -- task_id -> { reason, at, acknowledged }
  S._seen, S._seen_order = {}, {}
  S._cache = {}
  S._subs = S._subs or {}
end
S.reset()

-- ---------------------------------------------------------------- subscriptions
function S.subscribe(fn)
  table.insert(S._subs, fn)
  return function() for i, f in ipairs(S._subs) do if f == fn then table.remove(S._subs, i); return end end end
end
function S.emit(change)
  S.version = S.version + 1
  S._cache = {}
  change.version = S.version
  for _, fn in ipairs(vim.list_extend({}, S._subs)) do
    local ok, err = pcall(fn, change)
    if not ok then S.stats.subscriber_errors = S.stats.subscriber_errors + 1; S.last_subscriber_error = tostring(err) end
  end
end

-- ---------------------------------------------------------------- validation helpers
local function valid_task(t)
  return type(t) == "table" and P.valid_task_id(t.id) and P.TASK_STATES[t.state] ~= nil
end
local function remember_event(id)
  if not id then return true end
  if S._seen[id] then return false end
  S._seen[id] = true
  S._seen_order[#S._seen_order + 1] = id
  if #S._seen_order > S.LIMITS.seen_events then
    local old = table.remove(S._seen_order, 1); S._seen[old] = nil
  end
  return true
end

-- ---------------------------------------------------------------- snapshots and control
--- Apply a normalized snapshot (see adapter.lua). Idempotent. opts.connection=false leaves the
--- connection state to the caller (the v3 transport reports live only on the stream's status frame).
function S.apply_snapshot(snap, opts)
  if type(snap) ~= "table" or type(snap.tasks) ~= "table" then return false, "invalid snapshot" end
  local tasks = {}
  for _, t in ipairs(snap.tasks) do
    if not valid_task(t) then return false, "invalid task in snapshot: " .. vim.inspect(t and t.id) end
    tasks[t.id] = t
  end
  local attempts = {}
  for _, a in ipairs(snap.attempts or {}) do if type(a) == "table" and a.attempt_id then attempts[a.attempt_id] = a end end
  replace_into(S.tasks, tasks); replace_into(S.attempts, attempts)
  if snap.scheduler then S.scheduler = snap.scheduler end
  if snap.board then S.board = vim.tbl_extend("force", S.board, snap.board) end
  if snap.capabilities then S.board.capabilities = snap.capabilities end
  if snap.seq then S.seq = math.max(S.seq, snap.seq) end
  S.stats.snapshots = S.stats.snapshots + 1
  if not (opts and opts.connection == false) then S.connection.state, S.connection.last_success, S.connection.error = "live", vim.uv.now(), nil
  else S.connection.last_success = vim.uv.now() end
  S._refresh_attention()
  S.emit({ kind = "snapshot" })
  return true
end

--- Apply a normalized control event: { event_id, seq?, type, task?: normalized task, attempt?: attempt, task_id, ts }.
function S.apply_control(ev)
  if type(ev) ~= "table" or type(ev.type) ~= "string" then return false end
  if not remember_event(ev.event_id) then S.stats.duplicates = S.stats.duplicates + 1; return false end
  S.stats.events = S.stats.events + 1
  if ev.seq and ev.seq > S.seq then S.seq = ev.seq end
  local ids = {}
  if ev.task and valid_task(ev.task) then
    local cur = S.tasks[ev.task.id]
    -- attempt identity fence: a record for an older attempt never rewrites the current one
    if cur and cur.current_attempt_id and ev.attempt_id and ev.task.current_attempt_id and cur.current_attempt_id ~= ev.attempt_id and P.TERMINAL[cur.state] == nil and ev.type == "attempt.finished" then
      S.stats.duplicates = S.stats.duplicates + 1
    else
      S.tasks[ev.task.id] = ev.task; ids[#ids + 1] = ev.task.id
    end
  end
  if ev.attempt and ev.attempt.attempt_id then S.attempts[ev.attempt.attempt_id] = ev.attempt end
  if ev.scheduler then S.scheduler = ev.scheduler end
  S._refresh_attention()
  S.emit({ kind = "control", type = ev.type, ids = ids, task_id = ev.task_id, needs_refresh = ev.task == nil and ev.needs_refresh, historical = ev.historical })
  return true
end

function S.set_connection(fields)
  for k, v in pairs(fields) do S.connection[k] = v end
  S.emit({ kind = "connection" })
end

-- ---------------------------------------------------------------- activity (bounded)
--- Append a normalized activity record { event_id, ts, task_id, attempt_id?, kind, level, text, source, provenance, hidden? }.
function S.apply_activity(rec)
  if type(rec) ~= "table" or not rec.kind then return false end
  if not remember_event(rec.event_id) then S.stats.duplicates = S.stats.duplicates + 1; return false end
  local records = S.activity.records
  local last = records[#records]
  local size = #(rec.text or "") + 64
  -- coalesce repeats of the same task/kind/text
  if last and last.task_id == rec.task_id and last.kind == rec.kind and last.text == rec.text and rec.kind ~= "lifecycle" then
    last.count, last.ts_last = (last.count or 1) + 1, rec.ts
    S.emit({ kind = "activity", coalesced = true })
    return true
  end
  S.activity.seq = S.activity.seq + 1
  rec.n = S.activity.seq
  records[#records + 1] = rec
  S.activity.bytes = S.activity.bytes + size
  if rec.attempt_id then
    local pa = S.activity.per_attempt[rec.attempt_id] or { n = 0 }
    pa.n = pa.n + 1; S.activity.per_attempt[rec.attempt_id] = pa
  end
  while #records > S.LIMITS.activity_records or S.activity.bytes > S.LIMITS.activity_bytes do
    local old = table.remove(records, 1)
    S.activity.bytes = S.activity.bytes - (#(old.text or "") + 64)
    S.stats.dropped_activity = S.stats.dropped_activity + 1
    S.activity.gap = true
  end
  if rec.kind == "input_required" and rec.task_id then S.attention[rec.task_id] = { reason = "input_required", at = rec.ts, acknowledged = false } end
  S.emit({ kind = "activity", record = rec })
  return true
end

function S._refresh_attention()
  for id, t in pairs(S.tasks) do
    if t.state == "failed" then
      local cur = S.attention[id]
      local reason = t.outcome and t.outcome.reason == "orphaned" and "orphaned" or "failed"
      if not cur or cur.reason ~= reason or cur.outcome_at ~= (t.outcome and t.outcome.finished_at) then
        S.attention[id] = { reason = reason, at = t.outcome and t.outcome.finished_at, outcome_at = t.outcome and t.outcome.finished_at, acknowledged = false }
      end
    elseif S.attention[id] and S.attention[id].reason ~= "input_required" then S.attention[id] = nil end
  end
  for id in pairs(S.attention) do if not S.tasks[id] then S.attention[id] = nil end end
end
function S.acknowledge(id) if S.attention[id] then S.attention[id].acknowledged = true; S.emit({ kind = "attention" }) end end
function S.unacknowledged()
  local n = 0
  for _, a in pairs(S.attention) do if not a.acknowledged then n = n + 1 end end
  return n
end

-- ---------------------------------------------------------------- selectors (pure, cached)
function S.task(id) return S.tasks[id] end
function S.attempt(id) return S.attempts[id] end
function S.current_attempt(task_id)
  local t = S.tasks[task_id]
  if not t then return nil end
  if t.current_attempt_id then return S.attempts[t.current_attempt_id] end
  local atts = S.attempts_of(task_id)
  return atts[#atts]
end
function S.attempts_of(task_id)
  local key = "attempts:" .. task_id
  if S._cache[key] then return S._cache[key] end
  local out = {}
  for _, a in pairs(S.attempts) do if a.task_id == task_id then out[#out + 1] = a end end
  table.sort(out, function(a, b) return (a.ordinal or 0) < (b.ordinal or 0) end)
  S._cache[key] = out
  return out
end
function S.capability(name) return S.board.capabilities and S.board.capabilities[name] == true end

local GROUP_ORDER = { running = 1, attention = 2, queued = 3, finished = 4 }
S.GROUPS = { "running", "attention", "queued", "finished" }
local function group_of(t)
  if t.state == "running" then return "running" end
  if t.state == "failed" then return "attention" end
  if t.state == "queued" then return "queued" end
  return "finished"
end
S.group_of = group_of
--- Grouped, ordered task lists. filter: { text?: string, group?: string, provider?: string }.
function S.grouped(filter)
  filter = filter or {}
  local key = "grouped:" .. (filter.text or "") .. ":" .. (filter.group or "") .. ":" .. (filter.provider or "")
  if S._cache[key] then return S._cache[key] end
  local groups = { running = {}, attention = {}, queued = {}, finished = {} }
  local needle = filter.text and filter.text ~= "" and filter.text:lower() or nil
  local total, shown = 0, 0
  for _, t in pairs(S.tasks) do
    total = total + 1
    local g = group_of(t)
    local keep = true
    if filter.group and filter.group ~= "all" and filter.group ~= g then keep = false end
    if keep and filter.provider and t.provider ~= filter.provider then keep = false end
    if keep and needle then
      local hay = (t.id .. " " .. (t.title or "") .. " " .. (t.provider or "") .. " " .. (t.display or "")):lower()
      if not hay:find(needle, 1, true) then keep = false end
    end
    if keep then groups[g][#groups[g] + 1] = t; shown = shown + 1 end
  end
  -- running: stable order by start time; queued: numeric dispatch order; finished: newest first
  table.sort(groups.running, function(a, b)
    local sa = (S.attempts[a.current_attempt_id or ""] or {}).started_at or a.updated_at or ""
    local sb = (S.attempts[b.current_attempt_id or ""] or {}).started_at or b.updated_at or ""
    if sa ~= sb then return sa < sb end
    return a.id < b.id
  end)
  table.sort(groups.queued, P.compare_queue)
  local function finished_at(t) return t.outcome and t.outcome.finished_at or t.updated_at or "" end
  table.sort(groups.attention, function(a, b) local fa, fb = finished_at(a), finished_at(b); if fa ~= fb then return fa > fb end return a.id < b.id end)
  table.sort(groups.finished, function(a, b) local fa, fb = finished_at(a), finished_at(b); if fa ~= fb then return fa > fb end return a.id < b.id end)
  local res = { groups = groups, total = total, shown = shown }
  S._cache[key] = res
  return res
end
function S.counts()
  if S._cache.counts then return S._cache.counts end
  local c = { all = 0, running = 0, queued = 0, blocked = 0, attention = 0, finished = 0, states = { queued = 0, running = 0, succeeded = 0, failed = 0, cancelled = 0 } }
  for _, t in pairs(S.tasks) do
    c.all = c.all + 1
    c[group_of(t)] = c[group_of(t)] + 1
    if t.state == "queued" and t.blockers and #t.blockers > 0 then c.blocked = c.blocked + 1 end
    c.states[t.state] = (c.states[t.state] or 0) + 1
  end
  c.unacknowledged = S.unacknowledged()
  S._cache.counts = c
  return c
end
--- Activity filtered by scope { task_id?, attempt_id?, kinds?: set, min_level?: string, text?: string, show_hidden?: boolean }.
function S.activity_for(scope)
  scope = scope or {}
  local levels = { debug = 0, info = 1, warn = 2, error = 3 }
  local min = levels[scope.min_level or "info"] or 1
  local out = {}
  local needle = scope.text and scope.text ~= "" and scope.text:lower() or nil
  for _, r in ipairs(S.activity.records) do
    local keep = true
    if scope.task_id and r.task_id ~= scope.task_id then keep = false end
    if keep and scope.attempt_id and r.attempt_id ~= scope.attempt_id then keep = false end
    if keep and scope.provider and r.provider ~= scope.provider then keep = false end
    if keep and scope.kinds and not scope.kinds[r.kind] then keep = false end
    if keep and r.hidden and not scope.show_hidden then keep = false end
    if keep and (levels[r.level or "info"] or 1) < min then keep = false end
    if keep and needle and not ((r.text or "") .. " " .. (r.task_id or "")):lower():find(needle, 1, true) then keep = false end
    if keep then out[#out + 1] = r end
  end
  return out
end

return S
